with Ada.Characters.Handling;

with Graecus_Steps.Flows;
with Graecus_World; use Graecus_World;

package body Graecus_Steps.Implied is

   use type Graecus.Quality;

   --  Idle until the vol a premium implies is sought; its checks read
   --  it then, and the contract's vol is the implied one.
   type State is (Idle, Sought);

   type Guard_Kind is (Always, Seekable, Priceable, Numbers_Read, Named);

   type Action_Kind is
     (A_Nothing,
      A_Seek,
      A_Refuse_Unsought,
      A_Check_Round_Trip,
      A_Refuse_Unpriced,
      A_Check_Iv,
      A_Refuse_Numbers,
      A_Check_Quality,
      A_Refuse_Quality);

   function Quality_Word (Ctx : Step_Context) return String
   is (Fabula.Args.Word (Ctx.A, 1));

   function Name (Q : Graecus.Quality) return String
   is (Ada.Characters.Handling.To_Lower (Q'Image));

   function Is_Named (Ctx : Step_Context) return Boolean
   is (for some Q in Graecus.Quality => Name (Q) = Quality_Word (Ctx));

   function Evaluate
     (G : Guard_Kind; Ctx : Step_Context; Evt : Step_Kind) return Boolean
   is
      pragma Unreferenced (Evt);
   begin
      return
        (case G is
           when Always       => True,
           when Seekable     => Has (Ctx.W.Contract, Seeking_Terms),
           when Priceable    => Ready (Ctx, Priced_Terms),
           when Numbers_Read => Real_Read (Ctx, 1) and then Real_Read (Ctx, 2),
           when Named        => Is_Named (Ctx));
   end Evaluate;

   ---------------------------------------------------------------------
   --  Actions.
   ---------------------------------------------------------------------

   --  The vol the premium implies becomes the contract's vol, so a delta
   --  checked after it is the delta at that vol.
   procedure Seek (Ctx : in out Step_Context)
   with Pre => Has (Ctx.W.Contract, Seeking_Terms)
   is
   begin
      Seek (Ctx.W.Contract, Ctx.W.Implied.Iv, Ctx.W.Implied.Quality);
      Give (Ctx.W.Contract, Vol, Ctx.W.Implied.Iv);
   end Seek;

   --  Price the contract at its vol, then invert that price: the vol
   --  comes back, and computed.
   procedure Check_Recovers (Ctx : in out Step_Context)
   with Pre => Ready (Ctx, Priced_Terms)
   is
      Priced  : Graecus_World.Contract := Ctx.W.Contract;
      Iv      : Graecus.Vol_Range;
      Quality : Graecus.Quality;
   begin
      Give (Priced, Premium, Price_Of (Priced));
      Seek (Priced, Iv, Quality);
      Fabula.Check.Is_True
        (Ctx.R,
         Quality = Graecus.Computed,
         "the implied vol is " & Name (Quality));
      Check_Close
        (Ctx, "the implied vol", Iv, Priced.Value (Vol), Real_Of (Ctx));
   end Check_Recovers;

   procedure Execute
     (A : Action_Kind; Ctx : in out Step_Context; Evt : Step_Kind)
   is
      pragma Unreferenced (Evt);
   begin
      case A is
         when A_Nothing          =>
            null;

         when A_Seek             =>
            Seek (Ctx);

         when A_Refuse_Unsought  =>
            Refuse_Unready (Ctx, Seeking_Terms);

         when A_Check_Round_Trip =>
            Check_Recovers (Ctx);

         when A_Refuse_Unpriced  =>
            Refuse_Unready (Ctx, Priced_Terms);

         when A_Check_Iv         =>
            Check_Within (Ctx, "the implied vol", Ctx.W.Implied.Iv);

         when A_Refuse_Numbers   =>
            Refuse_Real (Ctx, (if Real_Read (Ctx, 1) then 2 else 1));

         when A_Check_Quality    =>
            Fabula.Check.Text_Equal
              (Ctx.R,
               Name (Ctx.W.Implied.Quality),
               Quality_Word (Ctx),
               "the implied vol");

         when A_Refuse_Quality   =>
            Fabula.Check.Fail_Step
              (Ctx.R,
               "no quality named "
               & Quality_Word (Ctx)
               & ": computed, faint or clamped");
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

   Implied          : constant Ev := (Kind => E_Implied);
   Check_Iv         : constant Ev := (Kind => E_Check_Iv);
   Check_Quality    : constant Ev := (Kind => E_Check_Quality);
   Check_Round_Trip : constant Ev := (Kind => E_Check_Round_Trip);

   --!format off
   Table : constant Transition_Table :=
     [Idle   + Implied          (Seekable)     / A_Seek             >= Sought,
      Idle   + Implied                         / A_Refuse_Unsought  >= Idle,
      Idle   + Check_Round_Trip (Priceable)    / A_Check_Round_Trip >= Idle,
      Idle   + Check_Round_Trip                / A_Refuse_Unpriced  >= Idle,
      Sought + Check_Iv         (Numbers_Read) / A_Check_Iv         >= Sought,
      Sought + Check_Iv                        / A_Refuse_Numbers   >= Sought,
      Sought + Check_Quality    (Named)        / A_Check_Quality    >= Sought,
      Sought + Check_Quality                   / A_Refuse_Quality   >= Sought];
   --!format on

   Current : State := Idle;

   procedure Offer
     (Ctx : in out Step_Context; Evt : Step_Kind; Handled : out Boolean) is
   begin
      Flow.Take (Table, Current, Ctx, Evt, Handled);
   end Offer;

   procedure Reset is
   begin
      Current := Idle;
   end Reset;

   function Phase return String
   is (Current'Image);

end Graecus_Steps.Implied;
