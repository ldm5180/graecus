with Graecus_Steps.Flows;
with Graecus_World; use Graecus_World;

package body Graecus_Steps.Smoothing is

   --  Each check weighs one sample on its own.
   type State is (Checking);

   type Guard_Kind is (Always, Gap_Weighable, Gap_Read);

   type Action_Kind is
     (A_Nothing,
      A_Check_Weight,
      A_Refuse_Gap,
      A_Check_Gap_Refused,
      A_Refuse_Number);

   --  The gap is the first capture; the weight and tolerance follow it.
   Gap_Capture : constant := 1;

   function Weighable (Ctx : Step_Context) return Boolean
   is (Ready (Ctx, No_Terms) and then Real_Of (Ctx, Gap_Capture) >= 0.0);

   function Evaluate
     (G : Guard_Kind; Ctx : Step_Context; Evt : Step_Kind) return Boolean
   is
      pragma Unreferenced (Evt);
   begin
      return
        (case G is
           when Always        => True,
           when Gap_Weighable => Weighable (Ctx),
           when Gap_Read      => Real_Read (Ctx, Gap_Capture));
   end Evaluate;

   ---------------------------------------------------------------------
   --  Actions.
   ---------------------------------------------------------------------

   --  Decay_Weight's precondition: a gap is never negative.
   procedure Refuse_Gap (Ctx : in out Step_Context) is
   begin
      if Ready (Ctx, No_Terms) then
         Fabula.Check.Fail_Step (Ctx.R, "a gap cannot be negative");
      else
         Refuse_Unready (Ctx, No_Terms);
      end if;
   end Refuse_Gap;

   --  Whether the weight takes X as a gap, rather than refusing it: the
   --  gap's subtype raises on a negative one.
   function Takes_Gap (X : Graecus.Real) return Boolean is
      W : Graecus.Real;
   begin
      W := Graecus.Decay_Weight (X);
      return W in 0.0 .. 1.0;
   exception
      when Constraint_Error =>
         return False;
   end Takes_Gap;

   procedure Execute
     (A : Action_Kind; Ctx : in out Step_Context; Evt : Step_Kind)
   is
      pragma Unreferenced (Evt);
   begin
      case A is
         when A_Nothing           =>
            null;

         when A_Check_Weight      =>
            Check_Close
              (Ctx,
               "the weight",
               Graecus.Decay_Weight (Real_Of (Ctx, Gap_Capture)),
               Real_Of (Ctx, 2),
               Real_Of (Ctx, 3));

         when A_Refuse_Gap        =>
            Refuse_Gap (Ctx);

         when A_Check_Gap_Refused =>
            Fabula.Check.Is_False
              (Ctx.R,
               Takes_Gap (Real_Of (Ctx, Gap_Capture)),
               "the gap was weighed");

         when A_Refuse_Number     =>
            Refuse_Real (Ctx, Gap_Capture);
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

   Check_Weight  : constant Ev := (Kind => E_Check_Weight);
   Check_Refused : constant Ev := (Kind => E_Check_Weight_Refused);

   --!format off
   Table : constant Transition_Table :=
     [Checking + Check_Weight (Gap_Weighable) / A_Check_Weight >= Checking,
      Checking + Check_Weight                 / A_Refuse_Gap   >= Checking,
      Checking + Check_Refused (Gap_Read)     / A_Check_Gap_Refused
                                                               >= Checking,
      Checking + Check_Refused                / A_Refuse_Number >= Checking];
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

end Graecus_Steps.Smoothing;
