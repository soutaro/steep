require_relative "test_helper"

class WorkerQueueTest < Minitest::Test
  WorkerQueue = Steep::Server::WorkerQueue

  def test_pop_in_order
    queue = WorkerQueue.new

    queue << :job1
    queue.push(:job2)

    assert_equal 2, queue.size
    refute queue.empty?

    assert_equal :job1, queue.pop
    assert_equal :job2, queue.pop

    assert queue.empty?
  end

  def test_urgent_jobs_go_first
    queue = WorkerQueue.new

    queue << :typecheck1
    queue.push(:hover1, urgent: true)
    queue << :typecheck2
    queue.push(:hover2, urgent: true)

    # The urgent jobs come out before the others, and the jobs of each kind keep their order
    assert_equal [:hover1, :hover2, :typecheck1, :typecheck2], 4.times.map { queue.pop }
  end

  def test_close
    queue = WorkerQueue.new

    queue << :job
    queue.close

    assert queue.closed?

    # The jobs left are popped, and then `nil`
    assert_equal :job, queue.pop
    assert_nil queue.pop

    assert_raises(ClosedQueueError) { queue << :another }
  end

  def test_pop_waits_for_push
    queue = WorkerQueue.new

    thread = Thread.new { queue.pop }
    Thread.pass until thread.status == "sleep"

    queue.push(:job, urgent: true)

    assert_equal :job, thread.value
  end

  def test_pop_wakes_up_on_close
    queue = WorkerQueue.new

    thread = Thread.new { queue.pop }
    Thread.pass until thread.status == "sleep"

    queue.close

    assert_nil thread.value
  end
end
