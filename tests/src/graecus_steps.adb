with Fabula.Check.Ints;
with Fabula.Numbers;

with Sml.Machines.Operators;
with Sml.Simple_Machines;

package body Graecus_Steps is

   --  One step as the machine sees it: the scenario, and the step's
   --  arguments, frame and outcome.
   type Step_Context is record
      W    : World;
      A    : Fabula.Args.List;
      Info : Fabula.Frames.Frame;
      R    : Fabula.Check.Outcome;
   end record;

   --  Empty until a step adds dollars; a check reads the total then.
   type State is (Empty, Summed);

   type Guard_Kind is (Always, Count_Read);

   type Action_Kind is (A_Nothing, A_Add, A_Refuse_Count, A_Check_Total);

   First_Capture : constant := 1;

   --  Whether the first capture reads as a whole number of zero or more.
   function Reads_As_Count (Ctx : Step_Context) return Boolean
   is (Fabula.Args.Count (Ctx.A) >= First_Capture
       and then Fabula.Args.Int (Ctx.A, First_Capture).Ok
       and then Fabula.Args.Int (Ctx.A, First_Capture).Value >= 0);

   function Evaluate
     (G : Guard_Kind; Ctx : Step_Context; Evt : Step_Kind) return Boolean
   is
      pragma Unreferenced (Evt);
   begin
      return
        (case G is
           when Always     => True,
           when Count_Read => Reads_As_Count (Ctx));
   end Evaluate;

   --  Fail the step: why its capture does not read as a count.
   procedure Refuse_Count (Ctx : in out Step_Context) is
      Read : constant Fabula.Numbers.Integer_Reads.Read :=
        Fabula.Args.Int (Ctx.A, First_Capture);
   begin
      if Read.Ok then
         Fabula.Check.Fail_Step (Ctx.R, "a count cannot be negative");
      else
         Fabula.Check.Ints.Fail_Read (Ctx.R, Read.Error);
      end if;
   end Refuse_Count;

   procedure Execute
     (A : Action_Kind; Ctx : in out Step_Context; Evt : Step_Kind)
   is
      pragma Unreferenced (Evt);
   begin
      case A is
         when A_Nothing      =>
            null;

         when A_Add          =>
            Ctx.W.Total :=
              Ctx.W.Total + Fabula.Args.Int (Ctx.A, First_Capture).Value;

         when A_Refuse_Count =>
            Refuse_Count (Ctx);

         when A_Check_Total  =>
            Fabula.Check.Ints.Equal
              (Ctx.R,
               Ctx.W.Total,
               Fabula.Args.Int (Ctx.A, First_Capture),
               "the total");
      end case;
   end Execute;

   package Machines is new
     Sml.Simple_Machines
       (State       => State,
        Event       => Step_Kind,
        Context     => Step_Context,
        Guard_Kind  => Guard_Kind,
        Action_Kind => Action_Kind,
        Evaluate    => Evaluate,
        Execute     => Execute);

   package Op is new Machines.Engine.Operators (Always, A_Nothing);

   use Machines;
   use Op;

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

   procedure Execute
     (S    : Step_Kind;
      Ctx  : in out World;
      A    : Fabula.Args.List;
      Info : Fabula.Frames.Frame;
      R    : in out Fabula.Check.Outcome)
   is
      Step    : Step_Context := (W => Ctx, A => A, Info => Info, R => R);
      M       : Machine := Make (Table, Initial => Current);
      Handled : Boolean;
   begin
      Engine.Process_Event (M, Step, S, Handled);
      Current := State_Of (M);
      Ctx := Step.W;
      R := Step.R;
      if not Handled then
         Fabula.Check.Fail_Step
           (R,
            S'Image
            & " is not a step this scenario can take now: "
            & Current'Image);
      end if;
   end Execute;

   procedure Run_Hook
     (H    : Hook_Kind;
      Ctx  : in out World;
      Info : Fabula.Frames.Frame;
      R    : in out Fabula.Check.Outcome)
   is
      pragma Unreferenced (H, Info, R);
   begin
      Ctx := (others => <>);
      Current := Empty;
   end Run_Hook;

end Graecus_Steps;
