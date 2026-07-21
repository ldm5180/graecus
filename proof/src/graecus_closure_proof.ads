--  The proof closure: withs the library unit so the analysis entry point
--  is explicit (gnatprove analyses every source in the tree; graecus has
--  no generics needing concrete instances).  The trusted Exp/Sqrt/Log
--  boundary inside the body stays SPARK_Mode Off with proved contracts.

with Graecus;

package Graecus_Closure_Proof
  with SPARK_Mode
is

end Graecus_Closure_Proof;
