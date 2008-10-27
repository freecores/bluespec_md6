//BSV includes
import RegFile::*;
import Connectable::*;
import GetPut::*;
import StmtFSM::*;

//CSG Lib includes
import PLBMaster::*;
import PLBMasterDefaultParameters::*;
import PLBMasterEmulator::*;

//Local includes 
import MD6Parameters::*;
import MD6Types::*;
import MD6Control::*;
import CompressionFunctionTypes::*;




module mkMD6ControlTest ();
  RegFile#(Bit#(26),BusWord) memory <- mkRegFileFullLoad("md6Input.hex");
  PLBMasterEmulator#(TExp#(26)) plbmaster <- mkPLBMasterEmulator(memory);
  MD6Control#(1,32) control <- mkMD6Control;
  // Hook up the system
  mkConnection(plbmaster.plbmaster.wordInput.put,control.wordOutput);
  mkConnection(control.wordInput,plbmaster.plbmaster.wordOutput.get);
  mkConnection(plbmaster.plbmaster.plbMasterCommandInput.put,control.outputCommand);


  Reg#(Bit#(32)) memPtr <- mkReg(0);

  RegFile#(Bit#(1), Bit#(32))  rfileSize <- mkRegFileFullLoad("inputSize.hex");
  RegFile#(Bit#(TLog#(MD6_c)), BusWord) rfileRes <- mkRegFileFullLoad("md6Result.hex");
  Reg#(Bit#(TAdd#(TLog#(MD6_c),1))) resPtr <- mkReg(0);
  
  let inputSize = (((rfileSize.sub(0))/fromInteger(8*valueof(MD6_b))) + 1)*fromInteger(valueof(MD6_b));


  Stmt s = seq
             control.keyRegister <= unpack(0);
             control.digestLength <= 512;
             control.sourceAddress <= 0; 
             $display("Offset is: %d", inputSize);
             control.destinationAddress <= 2*truncate(inputSize);
             control.bufferAddress <= 4*truncate(inputSize);
             $display("Bits input: %d", rfileSize.sub(0));
             control.bitSize <= zeroExtend(rfileSize.sub(0));  
             control.bigEndian <= True;         
             control.startDecode();
             await(!control.running);
             delay(100);
             for(resPtr <= 0;
                 resPtr < fromInteger(valueof(MD6_c)) - 8; //result is 512 bits I suppose  
                 resPtr <= resPtr+1)
             seq
               if(rfileRes.sub(truncate(resPtr)) != memory.sub(truncate(zeroExtend(resPtr) +  inputSize + 8)))
                 seq
                   $display("Offset: %d rfile: %d",zeroExtend(resPtr), rfileSize.sub(0));
                   $display("FAILED at %d, %h != %h", inputSize+zeroExtend(resPtr),rfileRes.sub(truncate(resPtr)),memory.sub(truncate(zeroExtend(resPtr) +  inputSize + 8)));
                   $finish;
                 endseq 
               else
                 seq
                   $display("Match at %d", zeroExtend(resPtr) + inputSize);
                 endseq
             endseq 
             $display("PASS");
             $finish;
           endseq;

  FSM fsm <- mkFSM(s);


  rule startFSM;
    fsm.start;
  endrule

endmodule