function load_env
   if test -f .env
      for pair in (cat .env | sed 's/#.*//g' | xargs)
          set -gx (string split -m 1 = $pair) 
      end
   end
end
