with Ada.Strings.Unbounded; use Ada.Strings.Unbounded;

with Fabula.Check.Reals;
with Fabula.Numbers;

with Graecus_Steps.Contract;
with Graecus_Steps.Deltas;
with Graecus_Steps.Implied;
with Graecus_Steps.Parity;
with Graecus_Steps.Pricing;

package body Graecus_Steps is

   procedure Then_Take (Ctx : in out Step_Context; Evt : Step_Kind) is
   begin
      Ctx.Has_Next := True;
      Ctx.Next := Evt;
   end Then_Take;

   function Real_Read (Ctx : Step_Context; N : Positive := 1) return Boolean
   is (N <= Fabula.Args.Count (Ctx.A) and then Fabula.Args.Real (Ctx.A, N).Ok);

   function Real_Of (Ctx : Step_Context; N : Positive := 1) return Graecus.Real
   is (Fabula.Args.Real (Ctx.A, N).Value);

   procedure Refuse_Real (Ctx : in out Step_Context; N : Positive := 1) is
   begin
      if N > Fabula.Args.Count (Ctx.A) then
         Fabula.Check.Fail_Step (Ctx.R, "the step has no number" & N'Image);
      else
         declare
            Read : constant Fabula.Numbers.Real_Reads.Read :=
              Fabula.Args.Real (Ctx.A, N);
         begin
            Fabula.Check.Reals.Fail_Read (Ctx.R, Read.Error);
         end;
      end if;
   end Refuse_Real;

   function Captures_Read (Ctx : Step_Context) return Boolean
   is (for all N in 1 .. Fabula.Args.Count (Ctx.A) => Real_Read (Ctx, N));

   function Ready
     (Ctx : Step_Context; Needs : Graecus_World.Term_Set) return Boolean
   is (Graecus_World.Has (Ctx.W.Contract, Needs) and then Captures_Read (Ctx));

   procedure Refuse_Unready
     (Ctx : in out Step_Context; Needs : Graecus_World.Term_Set) is
   begin
      if not Graecus_World.Has (Ctx.W.Contract, Needs) then
         Fabula.Check.Fail_Step
           (Ctx.R,
            "the contract has no "
            & Graecus_World.Name
                (Graecus_World.First_Missing (Ctx.W.Contract, Needs)));
         return;
      end if;
      for N in 1 .. Fabula.Args.Count (Ctx.A) loop
         if not Real_Read (Ctx, N) then
            Refuse_Real (Ctx, N);
            return;
         end if;
      end loop;
   end Refuse_Unready;

   procedure Check_Close
     (Ctx                  : in out Step_Context;
      What                 : String;
      Got, Want, Tolerance : Graecus.Real) is
   begin
      Fabula.Check.Is_True
        (Ctx.R,
         abs (Got - Want) <= Tolerance,
         What
         & " is "
         & Fabula.Check.Real_Image (Got)
         & ", not "
         & Fabula.Check.Real_Image (Want)
         & " within "
         & Fabula.Check.Real_Image (Tolerance));
   end Check_Close;

   procedure Check_Within
     (Ctx : in out Step_Context; What : String; Got : Graecus.Real) is
   begin
      Check_Close (Ctx, What, Got, Real_Of (Ctx, 1), Real_Of (Ctx, 2));
   end Check_Within;

   ---------------------------------------------------------------------
   --  The features as orthogonal regions: every step is offered to each,
   --  and each takes only its own.
   ---------------------------------------------------------------------

   type Offer_Access is
     access procedure
       (Ctx : in out Step_Context; Evt : Step_Kind; Handled : out Boolean);
   type Reset_Access is access procedure;
   type Phase_Access is access function return String;
   type Name_Access is access constant String;

   type Region is record
      Name  : Name_Access;
      Offer : Offer_Access;
      Reset : Reset_Access;
      Phase : Phase_Access;
   end record;

   Contract_Name : aliased constant String := "contract";
   Pricing_Name  : aliased constant String := "pricing";
   Delta_Name    : aliased constant String := "delta";
   Implied_Name  : aliased constant String := "implied vol";
   Parity_Name   : aliased constant String := "parity";

   --!format off
   Regions : constant array (Positive range <>) of Region :=
     [(Contract_Name'Access, Contract.Offer'Access, Contract.Reset'Access, Contract.Phase'Access),
      (Pricing_Name'Access,  Pricing.Offer'Access,  Pricing.Reset'Access,  Pricing.Phase'Access),
      (Delta_Name'Access,    Deltas.Offer'Access,   Deltas.Reset'Access,   Deltas.Phase'Access),
      (Implied_Name'Access,  Implied.Offer'Access,  Implied.Reset'Access,  Implied.Phase'Access),
      (Parity_Name'Access,   Parity.Offer'Access,   Parity.Reset'Access,   Parity.Phase'Access)];
   --!format on

   --  Every region's state, for the step no region would take.
   function Phases return String is
      Text : Unbounded_String;
   begin
      for G of Regions loop
         Append (Text, " " & G.Name.all & "=" & G.Phase.all);
      end loop;
      return To_String (Text);
   end Phases;

   procedure Execute
     (S    : Step_Kind;
      Ctx  : in out World;
      A    : Fabula.Args.List;
      Info : Fabula.Frames.Frame;
      R    : in out Fabula.Check.Outcome)
   is
      Step    : Step_Context :=
        (W => Ctx, A => A, Info => Info, R => R, others => <>);
      Taken   : Boolean := False;
      Handled : Boolean;
   begin
      for G of Regions loop
         G.Offer (Step, S, Handled);
         Taken := Taken or else Handled;
      end loop;
      Ctx := Step.W;
      R := Step.R;
      if not Taken then
         Fabula.Check.Fail_Step
           (R,
            S'Image & " is not a step this scenario can take now:" & Phases);
      end if;
   end Execute;

   procedure Run_Hook
     (H    : Hook_Kind;
      Ctx  : in out World;
      Info : Fabula.Frames.Frame;
      R    : in out Fabula.Check.Outcome)
   is
      pragma Unreferenced (Info, R);
   begin
      case H is
         when Fresh_World =>
            Ctx := (others => <>);
            for G of Regions loop
               G.Reset.all;
            end loop;
      end case;
   end Run_Hook;

end Graecus_Steps;
