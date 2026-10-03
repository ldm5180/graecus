--  How fast a new sample takes over (smoothing.feature): the weight a
--  sample earns from the gap before it.
--  A region of the registry: Offer takes this feature's steps, Reset
--  starts a scenario, Phase names its state.

package Graecus_Steps.Smoothing is

   procedure Offer
     (Ctx : in out Step_Context; Evt : Step_Kind; Handled : out Boolean);

   procedure Reset;

   function Phase return String;

end Graecus_Steps.Smoothing;
