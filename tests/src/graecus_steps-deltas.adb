with Graecus_Steps.Flows;
with Graecus_World; use Graecus_World;

package body Graecus_Steps.Deltas is

   --  Every check takes the delta of the contract as it stands.
   type State is (Checking);

   type Guard_Kind is (Always, Priceable, Sign_Named, Signable);

   type Action_Kind is
     (A_Nothing,
      A_Check_Delta,
      A_Check_Sign,
      A_Check_Sum,
      A_Refuse_Unpriced,
      A_Refuse_Sign);

   function Sign_Word (Ctx : Step_Context) return String
   is (Fabula.Args.Word (Ctx.A, 1));

   function Says_Positive (Ctx : Step_Context) return Boolean
   is (Sign_Word (Ctx) = "positive");

   function Is_Sign_Named (Ctx : Step_Context) return Boolean
   is (Says_Positive (Ctx) or else Sign_Word (Ctx) = "negative");

   function Evaluate
     (G : Guard_Kind; Ctx : Step_Context; Evt : Step_Kind) return Boolean
   is
      pragma Unreferenced (Evt);
   begin
      return
        (case G is
           when Always     => True,
           when Priceable  => Ready (Ctx, Priced_Terms),
           when Sign_Named => Is_Sign_Named (Ctx),
           when Signable   =>
             Is_Sign_Named (Ctx) and then Has (Ctx.W.Contract, Priced_Terms));
   end Evaluate;

   ---------------------------------------------------------------------
   --  Actions.
   ---------------------------------------------------------------------

   function Contract_Delta (Ctx : Step_Context) return Graecus.Real
   is (Delta_Of (Ctx.W.Contract, Ctx.W.Contract.Right))
   with Pre => Has (Ctx.W.Contract, Priced_Terms);

   procedure Check_Sign (Ctx : in out Step_Context)
   with Pre => Has (Ctx.W.Contract, Priced_Terms)
   is
      Got : constant Graecus.Real := Contract_Delta (Ctx);
   begin
      Fabula.Check.Is_True
        (Ctx.R,
         (if Says_Positive (Ctx) then Got > 0.0 else Got < 0.0),
         "the delta is " & Fabula.Check.Real_Image (Got));
   end Check_Sign;

   procedure Check_Sum (Ctx : in out Step_Context)
   with Pre => Ready (Ctx, Priced_Terms)
   is
   begin
      Check_Within
        (Ctx,
         "the call and put deltas' sum",
         Delta_Of (Ctx.W.Contract, Graecus.Call)
         + Delta_Of (Ctx.W.Contract, Graecus.Put));
   end Check_Sum;

   procedure Execute
     (A : Action_Kind; Ctx : in out Step_Context; Evt : Step_Kind)
   is
      pragma Unreferenced (Evt);
   begin
      case A is
         when A_Nothing         =>
            null;

         when A_Check_Delta     =>
            Check_Within (Ctx, "the delta", Contract_Delta (Ctx));

         when A_Check_Sign      =>
            Check_Sign (Ctx);

         when A_Check_Sum       =>
            Check_Sum (Ctx);

         when A_Refuse_Unpriced =>
            Refuse_Unready (Ctx, Priced_Terms);

         when A_Refuse_Sign     =>
            Fabula.Check.Fail_Step
              (Ctx.R,
               "no sign named " & Sign_Word (Ctx) & ": positive or negative");
      end case;
   end Execute;

   ---------------------------------------------------------------------
   --  The table.
   ---------------------------------------------------------------------

   package Flow is new
     Graecus_Steps.Flows
       (State       => State,
        Guard_Kind  => Guard_Kind,
        Action_Kind => Action_Kind,
        Evaluate    => Evaluate,
        Execute     => Execute,
        Always      => Always,
        Nothing     => A_Nothing);

   use Flow.Machines;
   use Flow.Op;

   Check_Delta      : constant Ev := (Kind => E_Check_Delta);
   Check_Delta_Sign : constant Ev := (Kind => E_Check_Delta_Sign);
   Check_Delta_Sum  : constant Ev := (Kind => E_Check_Delta_Sum);

   --!format off
   Table : constant Transition_Table :=
     [Checking + Check_Delta      (Priceable)  / A_Check_Delta     >= Checking,
      Checking + Check_Delta                   / A_Refuse_Unpriced >= Checking,
      Checking + Check_Delta_Sign (Signable)   / A_Check_Sign      >= Checking,
      Checking + Check_Delta_Sign (Sign_Named) / A_Refuse_Unpriced >= Checking,
      Checking + Check_Delta_Sign              / A_Refuse_Sign     >= Checking,
      Checking + Check_Delta_Sum  (Priceable)  / A_Check_Sum       >= Checking,
      Checking + Check_Delta_Sum               / A_Refuse_Unpriced >= Checking];
   --!format on

   Current : State := Checking;

   procedure Offer
     (Ctx : in out Step_Context; Evt : Step_Kind; Handled : out Boolean) is
   begin
      Flow.Take (Table, Current, Ctx, Evt, Handled);
   end Offer;

   procedure Reset is
   begin
      Current := Checking;
   end Reset;

   function Phase return String
   is (Current'Image);

end Graecus_Steps.Deltas;
