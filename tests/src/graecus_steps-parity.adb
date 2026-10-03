with Graecus_Steps.Flows;
with Graecus_World; use Graecus_World;

package body Graecus_Steps.Parity is

   --  Empty until a fixture row is loaded; its checks read it then.
   type State is (Empty, Loaded);

   type Guard_Kind is (Always, Row_Named, Number_Read);

   type Action_Kind is
     (A_Nothing,
      A_Load,
      A_Refuse_Row,
      A_Check_Iv,
      A_Check_Delta,
      A_Refuse_Number);

   --  The row's name is the first capture, its right the second.
   Name_Capture  : constant := 1;
   Right_Capture : constant := 2;

   function Row_Name (Ctx : Step_Context) return String
   is (Fabula.Args.Word (Ctx.A, Name_Capture));

   function Row_Right (Ctx : Step_Context) return String
   is (Fabula.Args.Word (Ctx.A, Right_Capture));

   function Evaluate
     (G : Guard_Kind; Ctx : Step_Context; Evt : Step_Kind) return Boolean
   is
      pragma Unreferenced (Evt);
   begin
      return
        (case G is
           when Always      => True,
           when Row_Named   => Has_Row (Row_Name (Ctx), Row_Right (Ctx)),
           when Number_Read => Real_Read (Ctx));
   end Evaluate;

   ---------------------------------------------------------------------
   --  Actions.
   ---------------------------------------------------------------------

   procedure Load (Ctx : in out Step_Context)
   with Pre => Has_Row (Row_Name (Ctx), Row_Right (Ctx))
   is
   begin
      Ctx.W.Row := Row (Row_Name (Ctx), Row_Right (Ctx));
      Ctx.W.Contract := Contract_Of (Ctx.W.Row);
   end Load;

   --  The row's contract at the vol its premium implies, as the parity
   --  test takes it.
   function At_Implied (Ctx : Step_Context) return Graecus_World.Contract is
      C       : Graecus_World.Contract := Contract_Of (Ctx.W.Row);
      Iv      : Graecus.Vol_Range;
      Quality : Graecus.Quality;
   begin
      Seek (C, Iv, Quality);
      Give (C, Vol, Iv);
      return C;
   end At_Implied;

   procedure Execute
     (A : Action_Kind; Ctx : in out Step_Context; Evt : Step_Kind)
   is
      pragma Unreferenced (Evt);
   begin
      case A is
         when A_Nothing       =>
            null;

         when A_Load          =>
            Load (Ctx);

         when A_Refuse_Row    =>
            Fabula.Check.Fail_Step
              (Ctx.R,
               "no fixture row named "
               & Row_Name (Ctx)
               & " "
               & Row_Right (Ctx));

         when A_Check_Iv      =>
            Check_Close
              (Ctx,
               "the implied vol",
               At_Implied (Ctx).Value (Vol),
               Ctx.W.Row.Go_Iv,
               Real_Of (Ctx));

         when A_Check_Delta   =>
            Check_Close
              (Ctx,
               "the delta",
               Delta_Of (At_Implied (Ctx), Ctx.W.Row.Right),
               Ctx.W.Row.Go_Delta,
               Real_Of (Ctx));

         when A_Refuse_Number =>
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

   Load_Row        : constant Ev := (Kind => E_Load_Row);
   Check_Row_Iv    : constant Ev := (Kind => E_Check_Row_Iv);
   Check_Row_Delta : constant Ev := (Kind => E_Check_Row_Delta);

   --!format off
   Table : constant Transition_Table :=
     [Empty  + Load_Row        (Row_Named)   / A_Load          >= Loaded,
      Empty  + Load_Row                      / A_Refuse_Row    >= Empty,
      Loaded + Check_Row_Iv    (Number_Read) / A_Check_Iv      >= Loaded,
      Loaded + Check_Row_Iv                  / A_Refuse_Number >= Loaded,
      Loaded + Check_Row_Delta (Number_Read) / A_Check_Delta   >= Loaded,
      Loaded + Check_Row_Delta               / A_Refuse_Number >= Loaded];
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

end Graecus_Steps.Parity;
