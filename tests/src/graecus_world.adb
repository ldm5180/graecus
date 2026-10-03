package body Graecus_World is

   function Field (Line : String; N : Positive) return String is
      Start : Positive := Line'First;
      Count : Positive := 1;
   begin
      for I in Line'Range loop
         if Line (I) = ',' then
            if Count = N then
               return Line (Start .. I - 1);
            end if;
            Count := Count + 1;
            Start := I + 1;
         end if;
      end loop;
      if Count = N then
         return Line (Start .. Line'Last);
      end if;
      return "";
   end Field;

end Graecus_World;
