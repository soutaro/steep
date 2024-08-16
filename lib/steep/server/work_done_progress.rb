module Steep
  module Server
    class WorkDoneProgress
      attr_reader :sender, :guid, :percentage

      def initialize(guid, &block)
        @sender = block
        @guid = guid
        @percentage = 0
      end

      def begin(title, message = nil, request_id:)
        sender.call(
          {
            id: request_id,
            method: "window/workDoneProgress/create",
            params: { token: guid }
          }
        )

        value = { kind: "begin", cancellable: false, title: title, percentage: percentage }
        value[:message] = message if message

        sender.call(
          {
            method: "$/progress",
            params: { token: guid, value: value }
          }
        )

        self
      end

      def report(percentage, message = nil)
        @percentage = percentage
        value = { kind: "report", percentage: percentage }
        value[:message] = message if message

        sender.call(
          {
            method: "$/progress",
            params: { token: guid, value: value }
          }
        )

        self
      end

      def end(message = nil)
        value = { kind: "end" }
        value[:message] = message if message

        sender.call(
          {
            method: "$/progress",
            params: { token: guid, value: value }
          }
        )

        self
      end
    end
  end
end
