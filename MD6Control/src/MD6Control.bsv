//----------------------------------------------------------------------//
// The MIT License 
// 
// Copyright (c) 2008 Kermin Fleming, kfleming@mit.edu 
// 
// Permission is hereby granted, free of charge, to any person 
// obtaining a copy of this software and associated documentation 
// files (the "Software"), to deal in the Software without 
// restriction, including without limitation the rights to use,
// copy, modify, merge, publish, distribute, sublicense, and/or sell
// copies of the Software, and to permit persons to whom the
// Software is furnished to do so, subject to the following conditions:
// 
// The above copyright notice and this permission notice shall be
// included in all copies or substantial portions of the Software.
// 
// THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND,
// EXPRESS OR IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES
// OF MERCHANTABILITY, FITNESS FOR A PARTICULAR PURPOSE AND
// NONINFRINGEMENT. IN NO EVENT SHALL THE AUTHORS OR COPYRIGHT
// HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER LIABILITY,
// WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING
// FROM, OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR
// OTHER DEALINGS IN THE SOFTWARE.
//----------------------------------------------------------------------//
//Global includes
import FIFO::*;
import Vector::*;
import GetPut::*;
import ConfigReg::*;

//CSG Lib includes
import PLBMaster::*;
import PLBMasterDefaultParameters::*;
 

//Local Includes
import MD6Parameters::*;
import MD6Types::*;
import MD6Library::*;
import CompressionFunction::*;
import CompressionFunctionTypes::*;
import CompressionFunctionLibrary::*;


interface MD6Control#(numeric type engines, numeric type steps);
  method ActionValue#(MD6Word) wordOutput();
  method Action wordInput(MD6Word inWord);
  method ActionValue#(PLBMasterCommand) outputCommand();
  method Action startDecode();
  method Bool running();
  interface Reg#(Vector#(MD6_k,Bit#(MD6_WordWidth))) keyRegister;
  interface Reg#(BlockAddr) sourceAddress;
  interface Reg#(BlockAddr) destinationAddress;
  interface Reg#(BlockAddr) bufferAddress;  
  interface Reg#(Bit#(TLog#(MD6_BitSize))) bitSize;
  interface Reg#(Bool) bigEndian;
  interface Reg#(DigestLength) digestLength;
endinterface


typedef TDiv#(TMul#(SizeOf#(BusWord),BeatsPerBurst), SizeOf#(MD6Word)) MD6WordsPerBurst;
typedef TDiv#(MD6_c,MD6WordsPerBurst) MD6BurstsPerHashStore;
typedef TDiv#(MD6_b,MD6WordsPerBurst) MD6BurstsPerHashLoad;
typedef TMul#(MD6_b,MD6_WordWidth) MD6BitsPerHashInput; 
typedef TMul#(MD6_c,MD6_WordWidth) MD6BitsPerHashOutput; 


typedef enum {
  Idle,
  IdleWait,
  LevelStart,
  LevelCompute
} ControlState deriving (Bits,Eq);


typedef enum {
    PadBlock,   
    NoPad,
    AllPad // Need a seperate rule for this one, not tied externally.
} IncomingBlock deriving (Bits, Eq);

typedef enum {
  Normal,
  LastInLevel,
  FinalBlock
} OutgoingBlock deriving (Bits, Eq);

module mkMD6Control (MD6Control#(engines,steps))
  provisos(Add#(steps,xxx,MD6_n),
           Add#(yyy,TLog#(steps),TLog#(MD6_n)),
           Add#(zzz,TLog#(steps),TLog#(MD6_b)),     
           Add#(wholeBlockBits,TLog#(MD6BitsPerHashInput),64));

  Vector#(engines,CompressionFunction#(steps)) md6Engines;

  if(valueof(steps)<16) 
    begin
      md6Engines <- replicateM(mkSimpleCompressionFunction);
    end
  else if(valueof(steps) % 16 == 0)
    begin
      md6Engines <- replicateM(mkMult16CompressionFunction);
    end 
  else 
    begin
      error("Unsupported Size");
    end

  /* These registers are externally visible.  Therefore, they must not be modified */  
  Reg#(BlockAddr) md6SourceAddr <- mkRegU();
  Reg#(BlockAddr) md6DestinationAddr <- mkRegU();
  Reg#(BlockAddr) md6BufferAddr <- mkRegU();  
  Reg#(Bit#(TLog#(MD6_BitSize))) md6BitSize <- mkRegU();
  Reg#(DigestLength) digestLengthReg <- mkRegU(); // Do we want to fold this across
                                               // The control engines themselves? 
  Reg#(Vector#(MD6_k,Bit#(MD6_WordWidth))) keyReg <- mkRegU();
  Reg#(Bool) bigEndianReg <- mkReg(False);
  

  /* These regs are used per computation */
  //Reg#(MD6_BitSize) bitsRemaining <- mkReg(0);
  Reg#(Bit#(TLog#(MD6_BitSize))) dataBlocksRemaining <- mkReg(0);
  Reg#(Bit#(TDiv#(MD6_b,MD6_c))) paddingBlocksRemaining <- mkReg(0);
  Reg#(TreeHeight)  currentHeight <- mkReg(0);  
  Reg#(Bit#(TLog#(MD6_b))) wordsIncoming <- mkReg(0);  
  Reg#(Bit#(TLog#(MD6_c))) wordsOutgoing <- mkReg(0);  
  Reg#(Bit#(TLog#(engines))) targetEngine <- mkReg(0);
  Reg#(ControlState) state <- mkReg(Idle); 
  Reg#(Bit#(TAdd#(1,TLog#(MD6BurstsPerHashLoad)))) loadCount <- mkReg(0); 
  Reg#(Bit#(TLog#(MD6BurstsPerHashStore))) storeCount <- mkReg(0); 
  Reg#(BlockAddr) sourceAddr <- mkReg(0);
  Reg#(BlockAddr) destAddr <- mkReg(0);
  Reg#(Bool) lastCompression <- mkReg(False);   
  Reg#(Bool) issuedStart <- mkReg(False);
  Reg#(Vector#(MD6_u,Bit#(MD6_WordWidth))) identifier <- mkRegU();

  FIFO#(Tuple2#(IncomingBlock,Bit#(TLog#(engines)))) inTokens <- mkFIFO;
  FIFO#(Tuple2#(OutgoingBlock,Bit#(TLog#(engines)))) outTokens <- mkFIFO;
  FIFO#(Bit#(TLog#(engines))) readyEngine <- mkFIFO;  
  FIFO#(PLBMasterCommand) plbCommand <- mkSizedFIFO(2); // why's this?
  
  // This needs to be as big as an input block.
  Reg#(Bit#(TLog#(MD6BitsPerHashInput))) tailNonZeroBits <- mkReg(0);
  Reg#(Bool) waitingForPad <- mkReg(False);

  function Action setupLevel()
    provisos(Add#(steps,xxx,MD6_n),
           Add#(yyy,TLog#(steps),TLog#(MD6_n)),
           Add#(zzz,TLog#(steps),TLog#(MD6_b)),
           Add#(wholeBlockBits,TLog#(MD6BitsPerHashInput),64));
    action
    // this is probably wrong
    Tuple2#(Bit#(wholeBlockBits),Bit#(TLog#(MD6BitsPerHashInput))) currentBits = split(md6BitSize);
    match {.wholeBlocks, .tailBits} = currentBits;
    $display("Current bits: %d %d", currentBits, md6BitSize); 
    $display("whole blocks: %d", wholeBlocks); 
    tailNonZeroBits <= tailBits; // Probably some sizing issue here.
    Bit#(TDiv#(MD6_b,MD6_c)) leftoverBlocks = truncate(wholeBlocks) + ((tailBits!=0)?1:0);
    Bit#(TDiv#(MD6_b,MD6_c)) paddingBlocks = truncate(fromInteger(valueof(TDiv#(MD6_b,MD6_c)))-zeroExtend(leftoverBlocks));    
    dataBlocksRemaining <= zeroExtend(wholeBlocks)+((tailBits!=0)?1:0); 
    paddingBlocksRemaining <= paddingBlocks;
    $display("Padding Blocks: %d", paddingBlocks);
    state <= LevelCompute; 
    if(state == Idle) 
      begin
        sourceAddr <= md6SourceAddr;
      end
    else
      begin
        sourceAddr <= md6BufferAddr;
      end
    identifier <= replicate(0);
    // Check for last compression
    if((wholeBlocks == 0) || ((wholeBlocks == 1) && (tailBits == 0)))
      begin
        $display("Setting the lastCompression");
        destAddr <= md6DestinationAddr;
        lastCompression <= True;
      end
    else
      begin
        destAddr <= md6BufferAddr;
        lastCompression <= False;
      end
    endaction
  endfunction
  
  rule levelRule (state == LevelStart && !waitingForPad);
    currentHeight <= currentHeight+1;
    setupLevel();
  endrule 

  rule issueStart(state == LevelCompute && !issuedStart);
       $display("calling issue start");
       issuedStart <= True;
       PaddingBits padding =  0; 
        $display("Starting engine: %d", targetEngine);
        if(targetEngine == fromInteger(valueof(engines)-1))
          begin
            targetEngine <= 0;
          end
        else
          begin
            targetEngine <= targetEngine + 1;
          end
        // Determine pad status
        // We have more regular data left to go. May need to count up on this one
        if(dataBlocksRemaining != 0)  // underflow may happen :(
          begin 
            dataBlocksRemaining <= dataBlocksRemaining - 1;
          end

        if((dataBlocksRemaining > 1) || ((dataBlocksRemaining!=0) && (tailNonZeroBits == 0))) // We might have a full block
          begin
            inTokens.enq(tuple2(NoPad,targetEngine));
          end
        else
          begin
            inTokens.enq(tuple2(PadBlock,targetEngine));
            waitingForPad <= True;
            // Define a block as MD6_c words.
            // In this case, we require some padding.
            padding = fromInteger(valueof(MD6_WordWidth)*valueof(MD6_b)) - zeroExtend(tailNonZeroBits);
            $display("tailNonZero: %d padding: %d",tailNonZeroBits,padding);
            // seems that tailNonZero bits is getting smashed
          end

        // Must also issue store token. 
        $display("outToken: %d", targetEngine);
        if(dataBlocksRemaining <= 1 && lastCompression)
          begin
            outTokens.enq(tuple2(FinalBlock,targetEngine));
          end 
        else if(dataBlocksRemaining <= 1) 
                  // in this case, we must wait until the level finishes processing 
                  // to start the next one. Not necessary for
                  // single engine.
          begin 
            outTokens.enq(tuple2(LastInLevel,targetEngine));
          end
        else
          begin
            outTokens.enq(tuple2(Normal,targetEngine));
          end
        $display("Setting CW: r: %d, l: %d, z:%d, p:%d, keylen: %d, d: %d", valueof(MD6_r),30,(lastCompression)?1:0,
                                           padding,  //Padding
                                           valueof(MD6_k)*valueof(MD6_WordWidth)/valueof(8), // Need Byte Size....
                                           valueof(MD6_d));

        // Start cutting here?


          Bit#(8) identLevel = currentHeight;
          Bit#(64) identifierFull = {identLevel,truncate(pack(identifier))};       
          identifier <= unpack(pack(identifier) + 1);
             
          md6Engines[targetEngine].start(defaultMD6R(digestLengthReg),64,(lastCompression)?1:0,padding, fromInteger(valueof(MD6_k)*valueof(MD6_WordWidth)/valueof(8)),digestLengthReg, unpack(pack(identifierFull)), keyReg);
          // why call this first?  This is a problem because we cannot overlap loads/stores.
  endrule


  rule issueStoreFinal (state == LevelCompute && (loadCount == fromInteger(valueof(MD6BurstsPerHashLoad))) &&
                   (storeCount == fromInteger(valueof(MD6BurstsPerHashStore)-1))  && issuedStart); 
            $display("Firiing Store Final");
            issuedStart <= False;
            loadCount <= 0;
            storeCount <= 0;
            // Check for the need to transition out of this state.
            // Hmm... This doesn't seem right probably only want to transition 
            // once we're sure when we're done.
            $display("In unoptimized clause dataBlocksRemaining: %d", dataBlocksRemaining);
            // Correct as we require 1 load/1 store at least  // Need to wait on level completion? 
            if(dataBlocksRemaining == 0)
              begin 
                state <= IdleWait; 
                if(lastCompression)
                  begin
                    $display("Setting state idlewait");
                
                  end
                else 
                  begin
                    //must fix md6BitSize here.
                    // Probably have to fix type...
                    Tuple2#(Bit#(wholeBlockBits),Bit#(TLog#(MD6BitsPerHashInput))) currentBits = split(md6BitSize);
                    Bit#(TLog#(MD6BitsPerHashOutput)) bottomZeros= 0;
                    match {.wholeBlocks, .tailBits} = currentBits;

                    md6BitSize <= zeroExtend({((tailBits!=0)?wholeBlocks+1:wholeBlocks), bottomZeros});
                
                  end
            end
          
        
            plbCommand.enq(tagged StorePage destAddr);
            destAddr <=  truncateLSB({destAddr,0} + (1 << (valueof(TLog#(WordsPerBurst))))); 
            // Actually issue the store here
  endrule

  // This may be problematic
  rule issueStore (state == LevelCompute && (loadCount == fromInteger(valueof(MD6BurstsPerHashLoad))) &&
                   (storeCount < fromInteger(valueof(MD6BurstsPerHashStore)-1))  && issuedStart); 
       $display("In optimized clause");
        storeCount <= storeCount + 1;
        plbCommand.enq(tagged StorePage destAddr);
        destAddr <=  truncateLSB({destAddr,0} + (1 << (valueof(TLog#(WordsPerBurst))))); 
  endrule  

  rule issueLoad((state == LevelCompute) && (loadCount < fromInteger(valueof(MD6BurstsPerHashLoad))));
    loadCount <= loadCount + 1;
    $display("Issue Load[%d of %d]: %d", loadCount+1, fromInteger(valueof(MD6BurstsPerHashLoad)),sourceAddr);
    plbCommand.enq(tagged LoadPage sourceAddr);
    sourceAddr <=  truncateLSB({sourceAddr,0} + (1 << (valueof(TLog#(WordsPerBurst)))));
  endrule


  // This rule will feed output from the MD6 engine to the memory controller
  method ActionValue#(MD6Word) wordOutput();
    match {.block, .engine} = outTokens.first;
    if(wordsOutgoing  == fromInteger(valueof(MD6_c) - 1))
      begin
       wordsOutgoing <= 0; 
       outTokens.deq;
       if(block == FinalBlock)
         begin
           $display("TIMING finish: %d", $time);
           state <= Idle; // At this point, we're really done...
         end
       else if(block == LastInLevel)
         begin
           state <= LevelStart;
         end
      end
    else
      begin
       wordsOutgoing <= wordsOutgoing + 1; 
      end
    $display("outgoing word");

    MD6Word endianCorrect <- md6Engines[engine].outputWord;
 
    MD6Word outWord;

    // MD6 is big endian.  If the system is little endian, we must swap.
    if(!bigEndianReg)
      begin
        $display("Big endian false");
        Vector#(TDiv#(MD6_WordWidth,8),Bit#(8)) vector = unpack(endianCorrect);
        outWord = pack(reverse(vector));
      end
    else
      begin
        outWord = endianCorrect;
      end   

    return outWord;
  endmethod  
  
  // This rule handles input from the outside world to the MD6 controller
  // This includes padding
  method Action wordInput(MD6Word endianCorrect);
    // Must deal with zero padding at the end of the 
    // first round.

    MD6Word inWord;

    // MD6 is big endian.  If the system is little endian, we must swap.
    if(!bigEndianReg)
      begin
        Vector#(TDiv#(MD6_WordWidth,8),Bit#(8)) vector = unpack(endianCorrect);
        inWord = pack(reverse(vector));
      end
    else
      begin
        inWord = endianCorrect;
      end   

    $display("inputWord called: %h", inWord);
    match {.blockType, .engine } = inTokens.first;

    if(wordsIncoming == fromInteger(valueof(MD6_b) - 1))
      begin
       wordsIncoming <= 0;
       if(blockType == PadBlock)
         begin
           waitingForPad <= False;
         end 
       inTokens.deq;
      end
    else 
      begin
       wordsIncoming <= wordsIncoming + 1; 
      end

    if(blockType == PadBlock)
      begin
        $display("Padblock, tailNonZeroBits: %d", tailNonZeroBits);
        // Now, pad the leftover bits to zero
        if(tailNonZeroBits > fromInteger(valueof(MD6_WordWidth)))
          begin
            tailNonZeroBits <= tailNonZeroBits - fromInteger(valueof(MD6_WordWidth));
            md6Engines[engine].inputWord(inWord);
          end
        else if(tailNonZeroBits > 0)
          begin // Might alter this to decrease impl area
            Bit#(TAdd#(1,TLog#(MD6_WordWidth))) shiftValue = truncate(64-tailNonZeroBits);
            Bit#(MD6_WordWidth) paddedWord = inWord & (~0 << shiftValue);   
            md6Engines[engine].inputWord(paddedWord);
            tailNonZeroBits <= 0;
          end
        else // All zeros from here.
          begin
            md6Engines[engine].inputWord(0);
          end
      end
    else if(blockType ==  NoPad)
      begin
        md6Engines[engine].inputWord(inWord);
      end
  endmethod

  method ActionValue#(PLBMasterCommand) outputCommand();
    plbCommand.deq;
    return plbCommand.first;
  endmethod

  // On the first pass only, we may have some tail non-zero bits.  we must pad these out.
  // All blocks must be padded to MD6_WordWidth
  method Action startDecode();
    if(state  == Idle)
      begin
        $display("TIMING start: %d", $time);
        currentHeight <= 1;
        setupLevel();
      end
  endmethod

  method Bool running();
    return !(state == Idle);
  endmethod 

  interface Reg keyRegister = keyReg;
  interface Reg sourceAddress = md6SourceAddr;
  interface Reg destinationAddress = md6DestinationAddr;
  interface Reg bufferAddress = md6BufferAddr;  
  interface Reg bitSize = md6BitSize;
  interface Reg bigEndian = bigEndianReg;
  interface Reg digestLength = digestLengthReg;

endmodule