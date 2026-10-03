--  The runner's smoke feature (smoke.feature): dollars added, then a
--  total checked.  A region of the registry: Offer takes this feature's
--  steps, Reset starts a scenario, Phase names its state.

package Graecus_Steps.Smoke is

   procedure Offer
     (Ctx : in out Step_Context; Evt : Step_Kind; Handled : out Boolean);

   procedure Reset;

   function Phase return String;

end Graecus_Steps.Smoke;
