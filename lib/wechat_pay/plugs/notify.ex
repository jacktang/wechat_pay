defmodule WechatPay.Plug.Notify do
  @moduledoc """
  Plug to handle callback from Wechat's payment gateway

  If the callback is success and verified, the result value will
  be assigned to private `:wechat_pay_result` key of the `Plug.Conn.t` object.

  ## Example

      defmodule MyApp.WechatPayController do
        use MyApp.Web, :controller

        plug WechatPay.Plug.Notify

        def callback(conn, _parasm) do
          data = conn.private[:wechat_pay_result]

          case data.result_code do
            "SUCCESS" ->
              IO.inspect data
              # %{
              #   appid: "wx2421b1c4370ec43b",
              #   attach: "支付测试",
              #   bank_type: "CFT",
              #   fee_type: "CNY",
              #   is_subscribe: "Y",
              #   mch_id: "10000100",
              #   nonce_str: "5d2b6c2a8db53831f7eda20af46e531c",
              #   openid: "oUpF8uMEb4qRXf22hE3X68TekukE",
              #   out_trade_no: "1409811653",
              #   result_code: "SUCCESS",
              #   return_code: "SUCCESS",
              #   sign: "594B6D97F089D24B55156CE09A5FF412",
              #   sub_mch_id: "10000100",
              #   time_end: "20140903131540",
              #   total_fee: "1",
              #   trade_type: "JSAPI",
              #   transaction_id: "1004400740201409030005092168"
              # }

              conn
              |> WechatPay.Plug.Notify.response_with_success_info
            _ ->
              conn
              |> send_resp(:unprocessable_entity, "")
          end
        end
      end
  """

  use Plug.Builder

  alias WechatPay.Utils.XMLParser
  alias WechatPay.Utils.Signature

  plug :handle_wechat_pay_callback

  @doc """
  Process the data comes from Wechat's Payment Gateway.

  If the data is success and verified, the result value will
  be assigned to private `:wechat_pay_result` key of the `Plug.Conn.t` object.
  """
  @spec handle_wechat_pay_callback(Plug.Conn.t, keyword()) :: Plug.Conn.t
  def handle_wechat_pay_callback(conn, _opts) do
    {:ok, body, conn} = Plug.Conn.read_body(conn)

    data = XMLParser.parse(body)

    with {:ok, data} <- process_result(data),
      {:ok, data} <- verify_sign(data)
    do
      conn
      |> put_private(:wechat_pay_result, data)
    else
      {:error, _reason} ->
        conn
        |> send_resp(:unprocessable_entity, "")
    end
  end

  @doc """
  Tell Wechat's Payment Gateway the notification is successfully handled.

  Response

      <xml>
        <return_code><![CDATA[SUCCESS]]></return_code>
        <return_msg><![CDATA[OK]]></return_msg>
      </xml>

  to server
  """
  @spec response_with_success_info(Plug.Conn.t) :: Plug.Conn.t
  def response_with_success_info(conn) do
    body = ~s"""
      <xml>
        <return_code><![CDATA[SUCCESS]]></return_code>
        <return_msg><![CDATA[OK]]></return_msg>
      </xml>
    """

    conn
    |> put_resp_content_type("application/xml")
    |> send_resp(:ok, body)
  end

  defp process_result(%{return_code: "SUCCESS"} = data) do
    {:ok, data}
  end
  defp process_result(%{return_code: "FAIL", return_msg: reason}) do
    {:error, reason}
  end

  defp verify_sign(data) do
    sign = data.sign

    calculated =
      data
      |> Map.delete(:sign)
      |> Signature.sign()

    if sign == calculated do
      {:ok, data}
    else
      {:error, "invalid signature"}
    end
  end
end
