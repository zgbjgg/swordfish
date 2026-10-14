import Config

config :tesla,
  adapter: Tesla.Adapter.Hackney

if File.exists?("config/#{config_env()}.exs") do
  import_config "#{config_env()}.exs"
end
