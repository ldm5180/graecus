with Graecus_Steps.Flows;
with Graecus_World; use Graecus_World;

package body Graecus_Steps.Contract is

   --  A contract takes its terms in any order, each as often as a
   --  scenario says it; every check reads it as it stands.
   type State is (Composing);

   type Guard_Kind is (Always, Fits_Envelope);

   type Action_Kind is (A_Nothing, A_Give, A_Refuse);

   --  The right is a contract step's first capture, the strike its second.
   Right_Capture  : constant := 1;
   Strike_Capture : constant := 2;

   function Term_Of (Evt : Set_Step) return Term
   is (case Evt is
         when E_Set_Spot     => Spot,
         when E_Set_Contract => Strike,
         when E_Set_Days     => Expiry,
         when E_Set_Vol      => Vol,
         when E_Set_Rate     => Rate);

   --  Which capture holds the number a step gives.
   function Number_Of (Evt : Set_Step) return Positive
   is (if Evt = E_Set_Contract then Strike_Capture else 1);

   function Right_Word (Ctx : Step_Context) return String
   is (Fabula.Args.Word (Ctx.A, Right_Capture));

   function Right_Named (Ctx : Step_Context; Evt : Set_Step) return Boolean
   is (Evt /= E_Set_Contract
       or else Right_Word (Ctx) = "call"
       or else Right_Word (Ctx) = "put");

   function Fits_Step (Ctx : Step_Context; Evt : Set_Step) return Boolean
   is (Right_Named (Ctx, Evt)
       and then Real_Read (Ctx, Number_Of (Evt))
       and then Fits (Term_Of (Evt), Real_Of (Ctx, Number_Of (Evt))));

   function Evaluate
     (G : Guard_Kind; Ctx : Step_Context; Evt : Step_Kind) return Boolean is
   begin
      return
        (case G is
           when Always        => True,
           when Fits_Envelope => Fits_Step (Ctx, Evt));
   end Evaluate;

   ---------------------------------------------------------------------
   --  Actions.
   ---------------------------------------------------------------------

   procedure Give (Ctx : in out Step_Context; Evt : Set_Step)
   with Pre => Fits_Step (Ctx, Evt)
   is
   begin
      if Evt = E_Set_Contract then
         Ctx.W.Contract.Right :=
           (if Right_Word (Ctx) = "call" then Graecus.Call else Graecus.Put);
      end if;
      Give (Ctx.W.Contract, Term_Of (Evt), Real_Of (Ctx, Number_Of (Evt)));
   end Give;

   --  Fail the step Fits_Envelope refused: the right, the number, or the
   --  envelope, whichever was wrong first.
   procedure Refuse (Ctx : in out Step_Context; Evt : Set_Step) is
   begin
      if not Right_Named (Ctx, Evt) then
         Fabula.Check.Fail_Step
           (Ctx.R, "no right named " & Right_Word (Ctx) & ": call or put");
      elsif not Real_Read (Ctx, Number_Of (Evt)) then
         Refuse_Real (Ctx, Number_Of (Evt));
      else
         Fabula.Check.Fail_Step (Ctx.R, Envelope (Term_Of (Evt)));
      end if;
   end Refuse;

   procedure Execute
     (A : Action_Kind; Ctx : in out Step_Context; Evt : Step_Kind) is
   begin
      case A is
         when A_Nothing =>
            null;

         when A_Give    =>
            Give (Ctx, Evt);

         when A_Refuse  =>
            Refuse (Ctx, Evt);
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

   Set_Spot     : constant Ev := (Kind => E_Set_Spot);
   Set_Contract : constant Ev := (Kind => E_Set_Contract);
   Set_Days     : constant Ev := (Kind => E_Set_Days);
   Set_Vol      : constant Ev := (Kind => E_Set_Vol);
   Set_Rate     : constant Ev := (Kind => E_Set_Rate);

   --!format off
   Table : constant Transition_Table :=
     [Composing + Set_Spot     (Fits_Envelope) / A_Give   >= Composing,
      Composing + Set_Spot                     / A_Refuse >= Composing,
      Composing + Set_Contract (Fits_Envelope) / A_Give   >= Composing,
      Composing + Set_Contract                 / A_Refuse >= Composing,
      Composing + Set_Days     (Fits_Envelope) / A_Give   >= Composing,
      Composing + Set_Days                     / A_Refuse >= Composing,
      Composing + Set_Vol      (Fits_Envelope) / A_Give   >= Composing,
      Composing + Set_Vol                      / A_Refuse >= Composing,
      Composing + Set_Rate     (Fits_Envelope) / A_Give   >= Composing,
      Composing + Set_Rate                     / A_Refuse >= Composing];
   --!format on

   Current : State := Composing;

   procedure Offer
     (Ctx : in out Step_Context; Evt : Step_Kind; Handled : out Boolean) is
   begin
      Flow.Take (Table, Current, Ctx, Evt, Handled);
   end Offer;

   procedure Reset is
   begin
      Current := Composing;
   end Reset;

   function Phase return String
   is (Current'Image);

end Graecus_Steps.Contract;
