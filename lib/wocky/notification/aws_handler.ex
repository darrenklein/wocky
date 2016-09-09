defmodule Wocky.Notification.AWSHandler do
  alias ExAws.SNS

  @behaviour :wocky_notification_handler

  @application_arn "arn:aws:sns:us-east-1:773488857071:app/APNS_SANDBOX/tinyrobot_dev"

  def register(user, device_id) do
    {:ok, %{body: body}} =
      @application_arn
      |> SNS.create_platform_endpoint(device_id, user)
      |> ExAws.request

    {:ok, xml} = :exml.parse(body)
    arn = :exml_query.path(xml, [
          {:element, "CreatePlatformEndpointResult"},
          {:element, "EndpointArn"},
          :cdata
        ])

    {:ok, arn}
  end

  def notify(endpoint, from, body) do
    subject = "Message Received from #{from}"
    {:ok, _response} =
      body
      |> SNS.publish(%{subject: subject, target_arn: endpoint})
      |> ExAws.request

    :ok
  end
end
