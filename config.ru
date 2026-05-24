# frozen_string_literal: true

# Opcional para servidores Rack no futuro. O launcher principal usa WEBrick via launcher_gui.rb.
run ->(_env) { [302, { 'Location' => 'http://127.0.0.1:4567' }, ['Use: bundle exec ruby launcher_gui.rb']] }
