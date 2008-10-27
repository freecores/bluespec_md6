import FIFOF::*;
import MD6Parameters::*;
import MD6Types::*;
import CompressionFunctionTypes::*;
import CompressionFunctionParameters::*;
import CompressionFunctionLibrary::*;
import Debug::*;
import SGenerator::*;
import Vector::*;

interface MD6ShiftRegister#(numeric type taps);
  method Vector#(taps,MD6Word) getT0;
  method Vector#(taps,MD6Word) getT1;
  method Vector#(taps,MD6Word) getT2;
  method Vector#(taps,MD6Word) getT3;
  method Vector#(taps,MD6Word) getT4;
  method Vector#(taps,MD6Word) getT5;
  method Action write(Vector#(taps,MD6Word) nextValues);
  method Action advance();
  interface Vector#(MD6_n, Reg#(MD6Word)) regs;
endinterface


module mkMD6ShiftRegister (MD6ShiftRegister#(taps))
  provisos(Add#(taps,yyy,MD6_n));
  Integer historyLength = valueof(taps);
  Vector#(MD6_n,Reg#(MD6Word)) t0 <- replicateM(mkReg(0));
  // we pulled out a subtraction of history length  
  method Vector#(taps,MD6Word) getT0;
    return takeAt(determineT0,readVReg(t0));
  endmethod 
 
  method Vector#(taps,MD6Word) getT1;
    return  takeAt(determineT1,readVReg(t0));
  endmethod

  method Vector#(taps,MD6Word) getT2;
    return  takeAt(determineT2,readVReg(t0));
  endmethod 

  method Vector#(taps,MD6Word) getT3;
    return  takeAt(determineT3,readVReg(t0));
  endmethod 

  method Vector#(taps,MD6Word) getT4;
    return  takeAt(determineT4,readVReg(t0));
  endmethod  

  method Vector#(taps,MD6Word) getT5;
    return  takeAt(determineT5,readVReg(t0));
  endmethod 

  method Action  write(Vector#(taps,MD6Word) nextword);
    writeVReg(takeAt(valueof(MD6_n)-valueof(taps),t0),nextword);
  endmethod 

  method Action advance();
    for(Integer i = 0; i < valueof(MD6_n); i=i+1)
      begin
        //$display("Advance ShiftState[%d]: %h",i, t0[i]);
      end
    for(Integer i = 0; i < valueof(MD6_n)-valueof(taps); i=i+1)
      begin
        t0[i] <= t0[i+valueof(taps)]; 
      end
  endmethod 

  interface regs = t0;
 
endmodule