--  What a contract is worth (pricing.feature): its price near a value,
--  or at least one, and the vols the envelope refuses.
--  A region of the registry: Offer takes this feature's steps, Reset
--  starts a scenario, Phase names its state.

package Graecus_Steps.Pricing is

   procedure Offer
     (Ctx : in out Step_Context; Evt : Step_Kind; Handled : out Boolean);

   procedure Reset;

   function Phase return String;

end Graecus_Steps.Pricing;
