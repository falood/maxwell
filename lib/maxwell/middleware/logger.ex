defmodule Maxwell.Middleware.Logger do
  @moduledoc  """
  Log the request and response by Logger, default log_level is :info.

  ### Examples

        # Client.ex
        use Maxwell.Builder ~(get)a
        @middleware Maxwell.Middleware.Log [log_level: :debug]

        def request do
          "/test" |> url |> get!
        end

  """
  use Maxwell.Middleware
  require Logger

  @levels [:info, :debug, :warn, :error]

  def init(opts) do
    case Keyword.pop(opts, :log_level) do
      {_, [_|_]} ->
        raise ArgumentError, "Logger Middleware Options doesn't accept wrong_option (:log_level)"
      {nil, _}                           -> [default: :info]
      {options, _} when is_list(options) -> parse_opts(options)
      {level, _}                         -> parse_opts([{level, :default}])
    end
  end

  def call(request_env, next_fn, options) do
    start_time = :os.timestamp()
    new_result = next_fn.(request_env)
    method = request_env.method |> to_string |> String.upcase
    case new_result do
      {:error, reason, _conn} ->
        error_reason = to_string(:io_lib.format("~p", [reason]))
        Logger.error("#{method} #{request_env.url}>> #{IO.ANSI.red}ERROR: " <> error_reason)
      %Maxwell.Conn{} = response_conn ->
        finish_time = :os.timestamp()
        duration = :timer.now_diff(finish_time, start_time)
        duration_ms = :io_lib.format("~.3f", [duration / 10_000])
        log_response_message(options, response_conn, duration_ms)
    end
    new_result
  end

  defp log_response_message(options, conn, ms) do
    %Maxwell.Conn{status: status, url: url, method: method} = conn
    level = get_level(options, status)
    color =
      case level do
        nil    -> nil
        :debug -> IO.ANSI.cyan
        :info  -> IO.ANSI.normal
        :warn  -> IO.ANSI.yellow
        :error -> IO.ANSI.red
      end

    unless is_nil(color) do
      message = "#{method} #{url} <<<#{color}#{status}(#{ms}ms)#{IO.ANSI.reset}\n#{inspect conn}"
      Logger.log(level, message)
    end
  end

  defp get_level([], _code),                      do: nil
  defp get_level([{code, level} | _], code),      do: level
  defp get_level([{from..to, level} | _], code)
  when code in from..to,                          do: level
  defp get_level([{:default, level} | _], _code), do: level
  defp get_level([_ | t], code),                  do: get_level(t, code)


  defp parse_opts(options),             do: parse_opts(options, [], nil)
  defp parse_opts([], result, nil),     do: Enum.reverse(result)
  defp parse_opts([], result, default), do: Enum.reverse([{:default, default} | result])

  defp parse_opts([{level, :default} | rest], result, nil) do
    check_level(level)
    parse_opts(rest, result, level)
  end

  defp parse_opts([{level, :default} | rest], result, level) do
    Logger.warn "Logger Middleware: default level defined multiple times."
    parse_opts(rest, result, level)
  end

  defp parse_opts([{_level, :default} | _rest], _result, _default) do
    raise ArgumentError, "Logger Middleware: default level conflict."
  end

  defp parse_opts([{level, codes} | rest], result, default) when is_list(codes) do
    check_level(level)
    result = Enum.reduce(codes, result, fn code, acc ->
      check_code(code)
      [{code, level} | acc]
    end)
    parse_opts(rest, result, default)
  end

  defp parse_opts([{level, code} | rest], result, default) do
    check_level(level)
    check_code(code)
    parse_opts(rest, [{code, level} | result], default)
  end


  defp check_level(level) when level in @levels,  do: :ok
  defp check_level(_level) do
    raise ArgumentError, "Logger Middleware: level only accepts #{inspect @levels}."
  end


  defp check_code(code) when is_integer(code), do: :ok
  defp check_code(_from.._to),                 do: :ok
  defp check_code(_any) do
    raise ArgumentError, "Logger Middleware: status code only accepts Integer and Range."
  end

end
