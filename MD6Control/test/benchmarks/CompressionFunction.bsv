import FIFOF::*;
import MD6Parameters::*;
import MD6Types::*;
import CompressionFunctionTypes::*;
import CompressionFunctionParameters::*;
import CompressionFunctionLibrary::*;
import Debug::*;
import SGenerator::*;
import Vector::*;
import MD6ShiftRegister::*;

Bool compressionDebug = True;

interface CompressionFunction#(numeric type taps);
  method Action start(Vector#(MD6_u,MD6Word) compressionIdentifierIn, Vector#(MD6_v,MD6Word) controlWordIn, Vector#(MD6_k,MD6Word) keyIn); // input all control information
  method Action inputWord(MD6Word word);
  method ActionValue#(MD6Word) outputWord();
  method Bit#(16) status();
endinterface

function MD6Word processStep(MD6Word t0,
                             MD6Word t1, 
                             MD6Word t2, 
                             MD6Word t3,
                             MD6Word t4,
                             MD6Word t5,
                             SGenerator sGenerator,
                             Bit#(TLog#(MD6_c)) step);
  
    ShiftFactor left = shiftIndexL(truncate(fromInteger(valueof(MD6_c) - 1) - step));
    ShiftFactor right = shiftIndexR(truncate(fromInteger(valueof(MD6_c) - 1) - step));     

    MD6Word sFactor = sGenerator.getS();
    MD6Word value = t0 ^ (t1 & t2) ^ (t3 & t4) ^ t5 ^ sFactor;
    MD6Word intermediate = ((value >> right) ^ value);
    return ((intermediate << left) ^ intermediate);
endfunction

typedef enum {
  Idle = 0,
  LocalInitialization = 1,
  LocalInitializationK = 2,
  LocalInitializationU = 3,
  LocalInitializationV = 4,
  ExternalDataIn = 5,
  Processing = 6,
  AuxiliaryShift = 7,
  ExternalDataOut = 8
} CompressionState deriving (Bits,Eq); 
 
// TODO: I should probably support multiple digest lengths

module mkSimpleCompressionFunction1 (CompressionFunction#(1));
  CompressionFunction#(1) compressor <- mkSimpleCompressionFunction;
  return compressor;
endmodule


module mkSimpleCompressionFunction (CompressionFunction#(taps))
  provisos(Add#(taps,xxx,MD6_n),
           Add#(yyy,TLog#(taps),TLog#(MD6_n)),
           Add#(zzz,TLog#(taps),TLog#(MD6_b)));
  /* The shift reg should look something like this:
  -> | shift0 | shift 1 | shift 2 | shift 3 | shift 4 | -> 
  */
  // As a parameterization, we could extra these FIFOs as a 
  // seperate module which we could imeplement as a sort of 
  // black box.  This is probably the right way to do things.
  // This plus 1 may or may not work.
  MD6ShiftRegister#(taps) shifter <- mkMD6ShiftRegister; 
  SGenerator sGenerator <- mkSGeneratorLogic;


  // Step Number is rather special.  It denotes the number of times
  // that enq will be called on the fifo chain. This includes
  // all init time functions
 
  Reg#(Round)              roundNumber <- mkReg(0);
  Reg#(Bit#(TLog#(MD6_n))) auxiliaryShift <- mkReg(0);
  Reg#(Bit#(TLog#(MD6_c))) stepInRound <- mkReg(0);
  Reg#(Bit#(TLog#(MD6_b))) externalDataCount <- mkReg(0);
  Reg#(Bit#(TLog#(TSub#(MD6_n,MD6_b)))) localInitializationCount <- mkReg(0);
  Reg#(CompressionState) state <- mkReg(Idle);                              
  //Reg#(Vector#(MD6_k,MD6Word)) key <- mkReg(replicate(0));
  //Reg#(Vector#(MD6_u,MD6Word)) compressionIdentifier <- mkReg(replicate(0));
  //Reg#(Vector#(MD6_v,MD6Word)) controlWord <- mkReg(replicate(0)); 

  Bit#(TLog#(TAdd#(MD6_c,1))) stepInRoundNext = zeroExtend(stepInRound) + fromInteger(valueof(taps));  
  let roundNumberNext = {1'b0,roundNumber} + 1;  
  Bit#(TLog#(TAdd#(MD6_b,1))) externalDataCountNext = zeroExtend(externalDataCount) + 1;  
  Bit#(TLog#(TAdd#(TSub#(MD6_n,MD6_b),1))) localInitializationCountNext = 
         zeroExtend(localInitializationCount) + 1;  
  Bit#(TLog#(TAdd#(MD6_n,1))) auxiliaryShiftNext = zeroExtend(auxiliaryShift) + 1;



  rule mainShift(state == Processing);
    if(stepInRoundNext == fromInteger(valueof(MD6_c)))
      begin
        stepInRound <= 0;
        roundNumber <= truncate(roundNumberNext);
        sGenerator.advanceRound(); // Need to advance round before next call of getS       
        if(roundNumberNext == fromInteger(valueof(MD6_r)))
          begin
            debug(compressionDebug,$display("Preparing to output"));
            state <= ExternalDataOut;
          end
      end
    else
      begin
        stepInRound <= truncate(stepInRoundNext);
      end

   if((roundNumber == 0) && (stepInRound == 0)) 
     begin
      for(Integer i = 0; i < valueof(MD6_n); i=i+1)
        begin
          debug(compressionDebug,$display("Starting ShiftState[%d]: %h",i, shifter.regs[i]));
        end
     end  
    

    function add(a,b);
       return a+b;
    endfunction

    function apply(a,b);
       return a(b);
    endfunction
 
    // The following crazy thing calculates the next state. It is vectorized
    Vector#(taps,MD6Word) nextVector = zipWith(apply,zipWith(apply,zipWith(apply,zipWith(apply,zipWith(apply,zipWith(apply,zipWith(apply,map(processStep,shifter.getT0),shifter.getT1),shifter.getT2),shifter.getT3),shifter.getT4),shifter.getT5),replicate(sGenerator)),zipWith(add,replicate(stepInRound),map(fromInteger,genVector)));

    /*
    for(Integer i = 0; i < valueof(taps); i=i+1)
      begin
        debug(compressionDebug,$display("NextWordShort: %h", nextVector[i]));
        debug(compressionDebug,$write("S: %h T5:%h T4:%h T3:%h T2:%h", sGenerator.getS(), shifter.getT5[i], shifter.getT4[i], shifter.getT3[i], shifter.getT2[i]));
        debug(compressionDebug,$display("T1:%h T0:%h Next MD6 Word: %h", shifter.getT1[i], shifter.getT0[i], nextVector[i]));
      end*/
    shifter.write(nextVector);    
    shifter.advance();
  endrule 

  // May want to switch to InitQ -> Idle state machine order to overlap some computation potentially.
  // May also want to explcitly intialize values in a state.
  method Action start(Vector#(MD6_u,MD6Word) compressionIdentifierIn, Vector#(MD6_v,MD6Word) controlWordIn, Vector#(MD6_k,MD6Word) keyIn) if(state == Idle); // input all control information
    state <= ExternalDataIn;
    externalDataCount <= 0;
    roundNumber <= 0; // Maybe put this somewhere else where its precense will be slightly more noticeable
    Integer i = valueof(MD6_b);
    // This stuff is in a reversed order
    for(Integer j = 0;i< valueof(MD6_b)+valueof(MD6_q); i=i+1, j=j+1)
       begin
         shifter.regs[i]._write(getQWord(fromInteger(j)));
       end
    for(Integer j = 0;i< valueof(MD6_b)+valueof(MD6_k)+valueof(MD6_q); i=i+1, j=j+1)
       begin
         shifter.regs[i]._write(keyIn[j]);
       end
    for(Integer j = 0;i< valueof(MD6_b)+valueof(MD6_u)+valueof(MD6_k)+valueof(MD6_q); i=i+1, j=j+1)
       begin
         shifter.regs[i]._write(compressionIdentifierIn[j]);
       end
    for(Integer j = 0;i< valueof(MD6_b)+valueof(MD6_v)+valueof(MD6_u)+valueof(MD6_k)+valueof(MD6_q); i=i+1, j=j+1)
       begin
         shifter.regs[i]._write(controlWordIn[j]);
       end

    sGenerator.resetS();
  endmethod


  method Action inputWord(MD6Word word) if(state == ExternalDataIn); // Specific range for inputing new hash values 
    if(externalDataCountNext == fromInteger(valueof(MD6_b)))
      begin
        externalDataCount <= 0;
        state <= Processing;
        
        for(Integer i  = 0; i < valueof(MD6_n); i = i + 1)
           begin
             $display("Shifter[%d] = %h",i,shifter.regs[i]);
           end
      end
    else
      begin
        externalDataCount <= truncate(externalDataCountNext);
      end
    //$display("externalDataCount: %d", externalDataCount);
    // Pull same trick as in output word here.  Must be careful about initialization, however, since those guys will be shifted over. 

    Vector#(taps,Reg#(MD6Word)) resultVec = take(shifter.regs);
    // This index is screwed up somehow.
    Bit#(TLog#(taps)) index = truncate(externalDataCount);

    //We start after all of the initialization stuff
    //Possible that bluespec may have issue here
    Vector#(taps,Reg#(MD6Word)) inputRegs = takeAt(valueof(MD6_n)-valueof(taps),shifter.regs);
    inputRegs[zeroExtend(index)]._write(word);
    if(index == 0) 
      begin 
        shifter.advance; // problems here.
        // this advance should occur MD6_b/taps - 1 times
      end
  endmethod

 
  method ActionValue#(MD6Word) outputWord() if( state == ExternalDataOut );
    if(externalDataCountNext == fromInteger(valueof(MD6_c)))
      begin
        externalDataCount <= 0;
        state <= Idle; 
        $display("Finished");
      end
    else
      begin
        externalDataCount <= truncate(externalDataCountNext);
      end   
    $display("Compression function is outputing");
    Vector#(taps,Reg#(MD6Word)) resultVec = takeAt(valueof(MD6_n)-valueof(MD6_c),shifter.regs);
    // This is probably wrong now.
    Bit#(TLog#(taps)) index = truncate(externalDataCount);
    if(index == ~0)
      begin 
        shifter.advance;
      end
    return resultVec[index]._read;
  endmethod

  method Bit#(16) status();
    return zeroExtend(pack(state));
  endmethod
endmodule