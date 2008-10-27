import MD6Types::*;

function Round defaultMD6R(DigestLength length);
  return 40+(length>>2);
endfunction