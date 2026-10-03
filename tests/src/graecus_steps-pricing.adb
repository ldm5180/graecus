with Graecus_Steps.Flows;
with Graecus_World; use Graecus_World;

package body Graecus_Steps.Pricing is

   --  Every check prices the contract as it stands, so a check may come
   --  at any point after the terms it reads.
   type State is (Checking);

   type Guard_Kind is (Always, Priceable, Number_Read);

   type Action_Kind is
     (A_Nothing,
      A_Check_Price,
      A_Check_Floor,
      A_Refuse_Unpriced,
      A_Check_Refused,
      A_Refuse_Number);

   function Evaluate
     (G : Guard_Kind; Ctx : Step_Context; Evt : Step_Kind) return Boolean
   is
      pragma Unreferenced (Evt);
   begin
      return
        (case G is
           when Always      => True,
           when Priceable   => Ready (Ctx, Priced_Terms),
           when Number_Read => Real_Read (Ctx));
   end Evaluate;

   ---------------------------------------------------------------------
   --  Actions.
   ---------------------------------------------------------------------

   --  Whether the crate's vol subtype takes X, rather than refusing it:
   --  a conversion to Vol_Range raises outside the envelope.
   function Takes_Vol (X : Graecus.Real) return Boolean is
   begin
      return Graecus.Vol_Range (X) = X;
   exception
      when Constraint_Error =>
         return False;
   end Takes_Vol;

   procedure Check_Floor (Ctx : in out Step_Context)
   with Pre => Ready (Ctx, Priced_Terms)
   is
      Got : constant Graecus.Real := Price_Of (Ctx.W.Contract);
   begin
      Fabula.Check.Is_True
        (Ctx.R,
         Got >= Real_Of (Ctx),
         "the price is " & Fabula.Check.Real_Image (Got));
   end Check_Floor;

   procedure Execute
     (A : Action_Kind; Ctx : in out Step_Context; Evt : Step_Kind)
   is
      pragma Unreferenced (Evt);
   begin
      case A is
         when A_Nothing         =>
            null;

         when A_Check_Price     =>
            Check_Within (Ctx, "the price", Price_Of (Ctx.W.Contract));

         when A_Check_Floor     =>
            Check_Floor (Ctx);

         when A_Refuse_Unpriced =>
            Refuse_Unready (Ctx, Priced_Terms);

         when A_Check_Refused   =>
            Fabula.Check.Is_False
              (Ctx.R, Takes_Vol (Real_Of (Ctx)), "the vol was taken");

         when A_Refuse_Number   =>
            Refuse_Real (Ctx);
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

   Check_Price       : constant Ev := (Kind => E_Check_Price);
   Check_Price_Floor : constant Ev := (Kind => E_Check_Price_Floor);
   Check_Vol_Refused : constant Ev := (Kind => E_Check_Vol_Refused);

   --!format off
   Table : constant Transition_Table :=
     [Checking + Check_Price       (Priceable)   / A_Check_Price     >= Checking,
      Checking + Check_Price                     / A_Refuse_Unpriced >= Checking,
      Checking + Check_Price_Floor (Priceable)   / A_Check_Floor     >= Checking,
      Checking + Check_Price_Floor               / A_Refuse_Unpriced >= Checking,
      Checking + Check_Vol_Refused (Number_Read) / A_Check_Refused   >= Checking,
      Checking + Check_Vol_Refused               / A_Refuse_Number   >= Checking];
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

end Graecus_Steps.Pricing;
