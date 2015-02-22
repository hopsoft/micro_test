require "os"
require "thread"

module PryTest
  class Runner
    class << self
      def terminate
        @terminate = true
      end

      def terminate?
        !!@terminate
      end
    end

    attr_reader :formatter, :options, :duration, :passed, :failed

    def initialize(formatter, options={})
      @formatter = formatter
      @options = options
      reset
    end

    def run
      formatter.before_suite(test_classes)
      run_test_classes
      formatter.after_suite(test_classes)
      failed
    end

    def reset
      @duration = 0
      tests.each { |t| t.reset }
    end

    def test_classes
      PryTest::Test.subclasses.shuffle
    end

    def tests
      test_classes.map{ |klass| klass.tests }.flatten
    end

    def failed_tests
      tests.select{ |test| test.invoked? && !test.passed? }
    end

    def failed
      failed_tests.length
    end

    def passed_tests
      tests.select{ |test| test.invoked? && test.passed? }
    end

    def passed
      passed_tests.length
    end

    private

    def run_test_classes
      start = Time.now
      test_classes.each { |test_class| run_test_class test_class }
      @duration = Time.now - start
      formatter.after_results(self)
    end

    def run_test_class(test_class)
      return if PryTest::Runner.terminate?
      test_queue ||= Queue.new if options[:async]
      formatter.before_class(test_class)
      test_class.tests.shuffle.each do |test|
        if options[:async]
          test_queue << test
        else
          test.invoke(formatter, options)
        end
      end
      formatter.after_class(test_class)
      run_threads(test_queue) if options[:async]
    end

    def run_threads(test_queue)
      threads = []
      thread_count = OS.cpu_count
      thread_count = 2 if thread_count < 2
      puts "PryTest is running #{thread_count} threads."
      thread_count.times do
        threads << Thread.new do
          while !test_queue.empty?
            Thread.current.kill if PryTest::Runner.terminate?
            test_queue.pop.invoke(formatter, options)
          end
        end
      end
      threads.each { |t| t.join }
    end

  end
end
