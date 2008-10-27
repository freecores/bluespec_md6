// The following are magic, externally defined parameters in MD6
// Other important parameters are derived from them.
// These parameters are used at a global level


`ifdef BIT64
typedef 16   MD6_c;
typedef 512  MD6_d; // Bits in final hashvalue
typedef 64   MD6_b;
typedef 178  MD6_r;

typedef 89   MD6_n; // This can definitely be derived from other constants at 
                    // the top level
typedef 15   MD6_q;
typedef 8    MD6_k;
typedef 1    MD6_v;
typedef 1    MD6_u;

typedef 64   MD6_WordWidth;
`endif

// All that appears to change for 
// different word widths is the WordWidth. 
// Other fields seem to get dropped.
`ifdef BIT32
typedef 32   MD6_c;
typedef 128  MD6_b;
typedef 178  MD6_r;

typedef 178  MD6_n; // This can definitely be derived from other constants at 
                    // the top level
typedef 30   MD6_q;
typedef 16   MD6_k;

typedef 2    MD6_v;
typedef 2    MD6_u;

typedef 32   MD6_WordWidth;
`endif

`ifdef BIT16
typedef 64   MD6_c;
typedef 256  MD6_b;
typedef 178  MD6_r;

typedef 178  MD6_n; // This can definitely be derived from other constants at 
                    // the top level
typedef 30   MD6_q;
typedef 16   MD6_k;
typedef 2    MD6_v;
typedef 2    MD6_u;

typedef 16   MD6_WordWidth;
`endif

`ifdef BIT8
typedef 32   MD6_c;
typedef 128  MD6_b;
typedef 178  MD6_r;

typedef 178  MD6_n; // This can definitely be derived from other constants at 
                    // the top level
typedef 30   MD6_q;
typedef 16   MD6_k;
typedef 2    MD6_v;
typedef 2    MD6_u;

typedef 32   MD6_WordWidth;
`endif