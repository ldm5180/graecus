with Fabula.Check.Ints;

with Graecus_Steps.Flows;

package body Graecus_Steps.Smoke is

   --  Empty until a step adds dollars; a check reads the total then.
   type State is (Empty, Summed);

   type Guard_Kind is (Always, Count_Read);

   type Action_Kind is (A_Nothing, A_Add, A_Refuse_Count, A_Check_Total);

   function Evaluate
     (G : Guard_Kind; Ctx : Step_Context; Evt : Step_Kind) return Boolean
   is
      pragma Unreferenced (Evt);
   begin
      return
        (case G is
           when Always     => True,
           when Count_Read => Graecus_Steps.Count_Read (Ctx));
   end Evaluate;

   procedure Execute
     (A : Action_Kind; Ctx : in out Step_Context; Evt : Step_Kind)
   is
      pragma Unreferenced (Evt);
   begin
      case A is
         when A_Nothing      =>
            null;

         when A_Add          =>
            Ctx.W.Total := Ctx.W.Total + Count (Ctx);

         when A_Refuse_Count =>
            Refuse_Count (Ctx);

         when A_Check_Total  =>
            Fabula.Check.Ints.Equal
              (Ctx.R, Ctx.W.Total, Fabula.Args.Int (Ctx.A, 1), "the total");
      end case;
   end Execute;

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

   Start         : constant Ev := (Kind => E_Start);
   Add_Dollars   : constant Ev := (Kind => E_Add_Dollars);
   Check_Dollars : constant Ev := (Kind => E_Check_Dollars);

   --!format off
   Table : constant Transition_Table :=
     [Empty  + Start                    / A_Nothing      >= Empty,
      Empty  + Add_Dollars (Count_Read) / A_Add          >= Summed,
      Empty  + Add_Dollars              / A_Refuse_Count >= Empty,
      Summed + Add_Dollars (Count_Read) / A_Add          >= Summed,
      Summed + Add_Dollars              / A_Refuse_Count >= Summed,
      Summed + Check_Dollars            / A_Check_Total  >= Summed];
   --!format on

   Current : State := Empty;

   procedure Offer
     (Ctx : in out Step_Context; Evt : Step_Kind; Handled : out Boolean) is
   begin
      Flow.Take (Table, Current, Ctx, Evt, Handled);
   end Offer;

   procedure Reset is
   begin
      Current := Empty;
   end Reset;

   function Phase return String
   is (Current'Image);

end Graecus_Steps.Smoke;
