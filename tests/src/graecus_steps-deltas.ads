--  Which way and how far a contract moves with the index (delta.feature):
--  the delta's sign, its value near one, and a call and put's sum.
--  A region of the registry: Offer takes this feature's steps, Reset
--  starts a scenario, Phase names its state.

package Graecus_Steps.Deltas is

   procedure Offer
     (Ctx : in out Step_Context; Evt : Step_Kind; Handled : out Boolean);

   procedure Reset;

   function Phase return String;

end Graecus_Steps.Deltas;
