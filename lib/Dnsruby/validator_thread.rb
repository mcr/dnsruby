module Dnsruby
  # Takes care of the validation for the SelectThread. If queries need to be
  # made in order to validate the response, then a separate thread is fired up
  # to do this.
  class ValidatorThread
    #    include Singleton
    def initialize(*args)
      @client_id, @client_queue, @response, @err, @query, @st, @res = args
      # Create the validation thread, and a queue to receive validation requests
      # Actually, need to have a thread per validator, as they make recursive calls.
      #      @@mutex = Mutex.new
      #      @@validation_queue = Queue.new
      #      @@validator_thread = Thread.new{
      #        do_validate
      #      }
    end
    def run
      # ONLY START THE NEW THREAD IF VALIDATION NEED OCCUR!!
      if (should_validate)
        Thread.new{
          do_validate
        }
      else
        do_validate
      end
    end


    #    def add_to_queue(item)
    #      print "ADding to validator queue\n"
    ##      @@mutex.synchronize{
    #        @@validation_queue.push(item)
    ##      }
    #    end
    def do_validate
      #      while (true)
      #        item = nil
      #        print "Waiting to pop validation item\n"
      ##        @@mutex.synchronize{
      #          item = @@validation_queue.pop
      ##        }
      #      print "Popped validation request\n"
      #        client_id, client_queue, response, err, query, st, res = item
      validate(@query, @response, @res)

      cache_if_valid(@query, @response)

      # Now send the response back to the client...
      @st.push_validation_response_to_select(@client_id, @client_queue, @response, @query, @res)


      #      end
    end

    def should_validate
      if (@query.do_validation)
        if (@res.dnssec)
          if (@response.security_level != Message::SecurityLevel::SECURE)
            return true
          end
        end
      end
      return false

    end

    def validate(query, response, res)
      if (should_validate)
        begin
          # So, we really need to be able to take the response out of the select thread, along
          # with the responsibility for sending the answer to the client.
          # Should we have a validator thread? Or a thread per validation?
          # Then, select thread gets response. It performs basic checks here.
          # After basic checks, the select-thread punts the response (along with queues, etc.)
          # to the validator thread.
          # The validator validates it (or just releases it with no validation), and then
          # sends the request to the client via the client queue.
          Dnssec.validate_with_query(query,response)
        rescue VerifyError => e
          response.security_error = e.to_s
          # Response security_level should already be set
          return false
        end
      end
    end

    def cache_if_valid(query, response)
      # ONLY cache the response if it is not an update response
      question = query.question()[0]
      if (query.do_caching && (query.class != Update) &&
            (question.qtype != Types.AXFR) && (question.qtype != Types.IXFR) &&
            (response.rcode == RCode.NOERROR) &&(!response.tsig) &&
            (query.class != Update) &&
            (response.header.ancount > 0))
        ## @TODO@ What about TSIG-signed responses?
        # Don't cache any packets with "*" in the query name! (RFC1034 sec 4.3.3)
        if (!question.qname.to_s.include?"*")
          # Now cache response RRSets
          if (query.header.rd)
            InternalResolver.cache_recursive(response);
          else
            InternalResolver.cache_authoritative(response);
          end
        end
      end

    end
  end
end
