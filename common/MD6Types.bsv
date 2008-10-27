import MD6Parameters::*;

typedef Bit#(MD6_WordWidth) MD6Word; 
typedef (TExp#(64)) MD6_BitSize; 


typedef Bit#(12) Round;
typedef Bit#(8)  TreeHeight;

typedef Bit#(4)  LastCompression; //One if last compression, else zero
typedef Bit#(16) PaddingBits;
typedef Bit#(8)  KeyLength;
typedef Bit#(12) DigestLength;