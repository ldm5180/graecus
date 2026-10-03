with Fabula.Main;

with Graecus_Steps;

--  The feature runner: Fabula.Main over the crate's step registry,
--  run over tests/features/ by `make features` and `alr test`.

procedure Graecus_Features is new
  Fabula.Main
    (Steps     => Graecus_Steps.Steps,
     Step_Defs => Graecus_Steps.Step_Defs,
     Hook_Defs => Graecus_Steps.Hook_Defs,
     Execute   => Graecus_Steps.Execute,
     Run_Hook  => Graecus_Steps.Run_Hook);
