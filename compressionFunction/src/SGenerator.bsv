//BSC Library includes
import Vector::*;

// CSG includes
import Debug::*;

// Local includes
import MD6Parameters::*;
import MD6Types::*;
import CompressionFunctionTypes::*;
import CompressionFunctionParameters::*;

Bool sgenDebug = False;

interface SGenerator#(numeric type size);
  method Vector#(size,MD6Word) getS();
  method Action advanceRound();
  method Action resetS();
endinterface


function MD6Word advanceRoundComb(MD6Word s);
  MD6Word sRotate = (s << 1) | zeroExtend(s[valueof(MD6_WordWidth)-1]);
  MD6Word nextS =  sRotate ^ (s & sStar());
  return nextS;
endfunction 


 

module mkSGeneratorLogic (SGenerator#(size));
  Vector#(size,Reg#(MD6Word)) s = newVector; // Grab S0 from parameters

  function applyN(f,arg,n);
    MD6Word seed = arg;
    for(Integer j =0; j < n; j = j+1)   
      begin
        seed = f(seed);
      end
    return seed;
  endfunction


  for(Integer i = 0; i < valueof(size); i = i+1) 
    begin
      s[i] <- mkReg(applyN(advanceRoundComb,s0(),i));
    end

  method Vector#(size,MD6Word) getS();
    return readVReg(s);
  endmethod

  method Action advanceRound();
    MD6Word seed = s[valueof(size)-1];
    $display("Calling advance Round");
    for(Integer i = 0; i < valueof(size); i = i+1) 
      begin
        MD6Word nextSeed = advanceRoundComb(seed);
        debug(sgenDebug,$display("Size: %d, Advancing s, old s: %h, new s:%h", valueof(size),s[i], nextSeed));
        s[i] <= nextSeed; // How did this work before??
        seed = nextSeed; 
      end
  endmethod

  method Action resetS();
    for(Integer i = 0; i < valueof(size); i = i+1) 
     begin
       s[i] <= applyN(advanceRoundComb,s0(),i);
     end
  endmethod
  
endmodule
