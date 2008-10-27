// CSG includes
import Debug::*;

// Local includes
import MD6Parameters::*;
import MD6Types::*;
import CompressionFunctionTypes::*;
import CompressionFunctionParameters::*;

Bool sgenDebug = False;

interface SGenerator;
  method MD6Word getS();
  method Action advanceRound();
  method Action resetS();
endinterface


module mkSGeneratorLogic (SGenerator);
  Reg#(MD6Word) s <- mkReg(s0()); // Grab S0 from parameters
  
  method MD6Word getS();
    return s;
  endmethod

  method Action advanceRound();
    MD6Word sRotate = (s << 1) | zeroExtend(s[valueof(MD6_WordWidth)-1]);
    MD6Word nextS =  sRotate ^ (s & sStar());
    s <= nextS;
    debug(sgenDebug,$display("Advancing s, old s: %h, new s:%h", s, nextS));
  endmethod

  method Action resetS();
    s <= s0();
  endmethod
  
endmodule
