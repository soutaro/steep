require_relative "test_helper"

# @rbs use Steep::*

class BaseWorkerTest < Minitest::Test
  include TestHelper
  include ShellHelper
  include LSPTestHelper

  include Steep

  # A worker whose jobs always raise, to exercise `BaseWorker`'s error handling.
  class RaisingWorker < Server::BaseWorker
    RequestJob = _ = Struct.new(:id, keyword_init: true)
    NotificationJob = _ = Struct.new(:guid, keyword_init: true)

    attr_reader :queue

    def initialize(project:, reader:, writer:)
      super
      @queue = Queue.new
    end

    def handle_request(request)
      case request[:method]
      when "test/request"
        queue << RequestJob.new(id: request[:id])
      when "test/notification"
        queue << NotificationJob.new(guid: "guid")
      end
    end

    def handle_job(job)
      raise "Boom"
    end
  end

  def dirs
    @dirs ||= []
  end

  def project
    Project.new(steepfile_path: current_dir + "Steepfile").tap do |project|
      Project::DSL.parse(project, <<~RUBY)
        target :lib do
          check "lib"
          signature "sig"
        end
      RUBY
    end
  end

  # Runs a worker, and shuts it down after the block returns -- even when an assertion fails,
  # so that a regression fails the test instead of hanging it.
  #
  # @rbs (Queue) { () -> void } -> void
  def run_worker(read_queue)
    worker = RaisingWorker.new(project: project, reader: worker_reader, writer: worker_writer)

    thread = Thread.new { worker.run() }

    begin
      yield
    ensure
      master_writer.write(id: -1, method: :shutdown, params: nil)
      pop_until(read_queue) {|message| message[:id] == -1 }
      master_writer.write(method: :exit)

      thread.join
      reader_pipe[1].close
      writer_pipe[1].close
    end
  end

  # @rbs (Queue) { (untyped) -> boolish } -> untyped
  def pop_until(read_queue)
    while message = read_queue.pop(timeout: 10)
      return message if yield(message)
    end

    flunk "Timeout: the worker didn't send the expected message"
  end

  def test_failed_request_job_returns_error_response
    in_tmpdir do
      with_master_read_queue do |read_queue|
        run_worker(read_queue) do
          master_writer.write(id: 123, method: "test/request", params: nil)

          response = pop_until(read_queue) {|message| message[:id] == 123 }

          refute_operator response, :key?, :result
          assert_equal LSP::Constant::ErrorCodes::INTERNAL_ERROR, response[:error][:code]
          assert_match(/Boom/, response[:error][:message])
        end
      end
    end
  end

  def test_failed_notification_job_reports_message_only
    in_tmpdir do
      with_master_read_queue do |read_queue|
        run_worker(read_queue) do
          master_writer.write(method: "test/notification", params: nil)

          # The job carries no request id, so `window/showMessage` is the only message sent.
          message = pop_until(read_queue) {|message| message[:method] == "window/showMessage" }

          assert_equal LSP::Constant::MessageType::ERROR, message[:params][:type]
          assert_match(/Boom/, message[:params][:message])
        end
      end
    end
  end
end
