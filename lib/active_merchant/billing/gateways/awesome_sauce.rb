require 'nokogiri'

module ActiveMerchant #:nodoc:
  module Billing #:nodoc:
    class AwesomeSauceGateway < Gateway

      self.test_url = 'http://sandbox.asgateway.com'
      self.live_url = 'prod.awesomesauce.com'

      self.supported_countries = ['US']
      self.default_currency = 'USD'

      self.supported_cardtypes = [:visa, :master, :american_express]

      self.homepage_url = 'http://asgateway.com/'
      self.display_name = 'Awesomesauce'

      ERROR_CODES = {
        '01' => 'Should never happen',
        '02' => 'Missing field',
        '03' => 'Bad format',
        '04' => 'Bad number',
        '05' => 'Arrest them!',
        '06' => 'Expired',
        '07' => 'Bad ref'
      }


      def initialize(options={})
        requires!(options, :login, :password)
        super
      end

      def purchase(money, creditcard, options={})

        # Example purchase request

        #<request>
        #  login info
        #  <action>purch</action>
        #  <amount>100.00</amount>
        #  <name>Bob</name>
        #  <number>4111111111111111</number>
        #  <cv2>123</cv2>
        #  <exp>012019</exp>
        #</request>

        # Use basic object builder to build up xml

        request = build_xml_request do |doc|
          doc.action('purch')
          add_invoice(doc, money, options)
          add_payment(doc, creditcard)
        end
        
        # issue post
        commit('/api/auth', request)
      end


      def authorize(money, creditcard, options={})

        # Example auth request

        #<request>
        #  login info
        #  <action>auth</action>
        #  <amount>100.00</amount>
        #  <name>Bob</name>
        #  <number>4111111111111111</number>
        #  <cv2>123</cv2>
        #  <exp>012019</exp>
        #</request>

        # Use basic object builder to build up xml

        request = build_xml_request do |doc|
          doc.action('auth')
          add_invoice(doc, money, options)
          add_payment(doc, creditcard)
        end

        commit('/api/auth', request)
      end

      def capture(money, identification, options={})
        # Example capture request

        #<request>
        #  login info
        #  <action>capture</action>
        #  <ref>id</ref>
        #</request>

        # Use basic object builder to build up xml

        request = build_xml_request do |doc|
          doc.action('capture')
          doc.ref(identification)
        end

        commit('/api/ref', request)
      end

      def refund(money, identification, options={})
        # Delegate to void method
        void(identification, options)
      end


      def credit(money, identification, options = {})
        ActiveMerchant.deprecated CREDIT_DEPRECATION_MESSAGE
      end


      def void(identification, options={})
        # Example void request

        #<request>
        #  login info
        #  <action>cancel</action>
        #  <ref>id</ref>
        #</request>

        # Use basic object builder to build up xml

        request = build_xml_request do |doc|
          doc.action('cancel')
          doc.ref(identification)
        end

        commit('/api/ref', request)
      end

      def verify(creditcard, options={})
        MultiResponse.run(:use_first_response) do |r|
          r.process { authorize(100, creditcard, options) }
          r.process(:ignore_result) { void(r.authorization, options) }
        end
      end

      def supports_scrubbing?
        true
      end


      # Filter out gateway credentials, PAN, and other sensitive CC data
      def scrub(transcript)
        transcript.
          gsub(%r((<merchant>).+(</merchant>)), '\1[FILTERED]\2').
          gsub(%r((<secret>).+(</secret>)), '\1[FILTERED]\2').
          gsub(%r((<number>).+(</number>)), '\1[FILTERED]\2').
          gsub(%r((<cv2>).+(</cv2>)), '\1[FILTERED]\2').
          gsub(%r((<exp>).+(</exp>)), '\1[FILTERED]\2')
      end

      private

      # Helper method to generate amount
      def add_invoice(doc, money, options)
        doc.amount(amount(money))
      end


      # Helper method to generate credit card payment data
      def add_payment(doc, creditcard)
        doc.name(creditcard.name)
        doc.number(creditcard.number)
        doc.cv2(creditcard.verification_value)
        doc.exp(expdate(creditcard))
      end


      # Helper to add authentication data
      def add_auth(doc)
        doc.merchant(@options[:login])
        doc.secret(@options[:password])
      end

      # Override inherited expdate to have year with four digits
      def expdate(credit_card)
        "#{format(credit_card.month, :two_digits)}#{format(credit_card.year, :four_digits)}"
      end

      # Generate xml request using Builder object
      def build_xml_request
        Nokogiri::XML::Builder.new do |xml|
          xml.request do
            add_auth(xml)
            yield(xml)
          end
        end.to_xml
      end


      # Post the request to the appropriate rest endpoint
      def commit(endpoint, request)
        url = (test? ? test_url : live_url)

        # combine url with rest endpoint
        full_url = url + endpoint

        begin
          raw_response = ssl_post(full_url, request)
        rescue ResponseError => e
          raw_response = e.response.body
        end

        response = parse(raw_response)

        Response.new(
          success_from(response),
          message_from(response),
          response,
          authorization: authorization_from(response),
          avs_result: AVSResult.new(code: response[:response_avs_code]),
          cvv_result: CVVResult.new(response[:response_cvv_code]),
          test: test?,
          error_code: error_code_from(response)
        )
      end


      # Parse the xml response by
      # creating the hash keys from the response xml tag names
      # e.g. :response_success, :response_err, :response_code, :response_id

      def parse(body)

        response = {}

        doc = Nokogiri::XML(body)
        doc.remove_namespaces!

        doc.xpath('*').each do |node|
          if (node.elements.empty?)
            response[node.name.to_sym] = node.text
          else
            node.elements.each do |childnode| # children only one level deep
              name = "#{node.name}_#{childnode.name}"
              response[name.to_sym] = childnode.text
            end
          end
        end

        response
      end


      # Extract success true or false value
      def success_from(response)
        #response_success 	true or false
        response[:response_success].to_s == 'true' ? true : false
      end

      # Extract msg about what happened
      def message_from(response)
        if success_from(response) == true
          'SUCCESS'
        elsif response[:response_err] != nil
          #response_err 	a message about what happened
          err_msg = response[:response_err]
          err_code_msg = error_code_from(response)
          "FAILURE #{err_msg} - #{err_code_msg}"
        elsif response[:error] != nil
          msg = response[:error]
          "FAILURE - #{msg}"
        else
          "FAILURE Oops"
        end
      end

      # Extract reference for operation
      def authorization_from(response)
        #response_id 	a reference for the operation 
        response[:response_id]
      end

      # Extract error message from code about what happened
      def error_code_from(response)
        unless success_from(response)
          #response_code 	a code about what happened
          ERROR_CODES[response[:response_code]]
        end
      end

    end # end class
  end # end module
end # end module
