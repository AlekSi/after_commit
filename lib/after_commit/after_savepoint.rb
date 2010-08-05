# Fix problems caused because tests all run in a single transaction.

# The single transaction means that after_commit callback never happens in tests.  Instead use savepoints.

module AfterCommit
  module AfterSavepoint
    def self.included(klass)
      klass.class_eval do
        class << self
          def include_after_savepoint_extensions
            base = ::ActiveRecord::ConnectionAdapters::AbstractAdapter
            Object.subclasses_of(base).each do |klass|
              include_after_savepoint_extension klass
            end
        
            if defined?(JRUBY_VERSION) and defined?(JdbcSpec::MySQL)
              include_after_savepoint_extension JdbcSpec::MySQL
            end
          end

          private
      
          def include_after_savepoint_extension(adapter)
            additions = AfterCommit::TestConnectionAdapters
            unless adapter.included_modules.include?(additions)
              adapter.send :include, additions
            end
          end
        end
      end
    end
  end

  module TestConnectionAdapters
    def self.included(base)
      base.class_eval do

        # matches commit_db_transaction_with_callback
        def release_savepoint_with_callback
          increment_transaction_pointer
          result    = nil
          begin
            trigger_before_commit_callbacks
            trigger_before_commit_on_create_callbacks
            trigger_before_commit_on_update_callbacks
            trigger_before_commit_on_save_callbacks
            trigger_before_commit_on_destroy_callbacks

            result = release_savepoint_without_callback
            @disable_rollback = true

            trigger_after_commit_callbacks
            trigger_after_commit_on_create_callbacks
            trigger_after_commit_on_update_callbacks
            trigger_after_commit_on_save_callbacks
            trigger_after_commit_on_destroy_callbacks
            result
          rescue
            # Need to decrement the transaction pointer before calling
            # rollback... to ensure it is not incremented twice
            unless @disable_rollback
              decrement_transaction_pointer
              @already_decremented = true
            end

            # We still want to raise the exception.
            raise
          ensure
            AfterCommit.cleanup(self)
            decrement_transaction_pointer unless @already_decremented
          end
        end
        alias_method_chain :release_savepoint, :callback

        # matches rollback_db_transaction_with_callback
        def rollback_to_savepoint_with_callback
          return if @disable_rollback
          increment_transaction_pointer
          begin
            result = nil
            trigger_before_rollback_callbacks
            result = rollback_to_savepoint_without_callback
            trigger_after_rollback_callbacks
            result
          ensure
            AfterCommit.cleanup(self)
            decrement_transaction_pointer
          end
          decrement_transaction_pointer
        end
        alias_method_chain :rollback_to_savepoint, :callback
      end
    end
  end
end
