require 'test_helper'

class AwesomeSauceTest < Test::Unit::TestCase
  include CommStub

  def setup
    @gateway = AwesomeSauceGateway.new(
      :login => 'test-api', 
      :password => 'c271ee995dd79671dc19f3ba4bb435e26bee68b0e831b7e9e4ae858c1584e0a33bc93b8d9ca3cedc'
    )

    @credit_card = credit_card('4000100011112224')
    @declined_card = credit_card('40003')
    @amount = 10000 # integer value in cents, so $100.00 dollars

    @options = {
      billing_address: address,
      description: 'Store Purchase'
    }
  end

  def test_successful_purchase
    @gateway.expects(:ssl_post).returns(successful_purchase_response)

    response = @gateway.purchase(@amount, @credit_card, @options)
    assert_success response

    assert_equal '47654', response.authorization
    assert response.test?
  end

  def test_failed_purchase
    @gateway.expects(:ssl_post).returns(failed_purchase_response)

    response = @gateway.purchase(@amount, @declined_card, @options)
    assert_failure response

    assert_equal '47655', response.authorization
    assert response.test?
  end

  def test_successful_authorize_and_capture
    @gateway.expects(:ssl_post).returns(successful_authorize_response)

    auth = @gateway.authorize(@amount, @credit_card, @options)
    assert_success auth

    @gateway.expects(:ssl_post).returns(successful_capture_response)

    assert capture = @gateway.capture(@amount, auth.authorization)
    assert_success capture
  end

  def test_failed_authorize
    @gateway.expects(:ssl_post).returns(failed_authorize_response)

    response = @gateway.authorize(@amount, @declined_card, @options)
    assert_failure response
    assert_equal 'FAILURE number - Bad format', response.message
  end

  def test_failed_capture
    @gateway.expects(:ssl_post).returns(failed_capture_response)

    response = @gateway.capture(@amount, '')
    assert_failure response
    assert_equal 'FAILURE Oops', response.message
  end

  def test_successful_refund
    @gateway.expects(:ssl_post).returns(successful_purchase_response)

    purchase = @gateway.purchase(@amount, @credit_card, @options)
    assert_success purchase

    @gateway.expects(:ssl_post).returns(successful_refund_response)

    assert refund = @gateway.refund(@amount, purchase.authorization)
    assert_success refund
    assert_equal 'SUCCESS', refund.message
  end

  def test_failed_refund
    @gateway.expects(:ssl_post).returns(failed_refund_response)

    response = @gateway.refund(@amount, '')
    assert_failure response
    assert_equal 'FAILURE Oops', response.message
  end

  def test_successful_void
    @gateway.expects(:ssl_post).returns(successful_authorize_response)

    auth = @gateway.authorize(@amount, @credit_card, @options)
    assert_success auth
    assert_equal '47993', auth.authorization

    @gateway.expects(:ssl_post).returns(successful_void_response)

    assert void = @gateway.void(auth.authorization)
    assert_success void
    assert_equal 'SUCCESS', void.message
    assert_equal '47994', void.authorization
  end

  def test_failed_void
    @gateway.expects(:ssl_post).returns(failed_void_response)

    response = @gateway.void('')
    assert_failure response
    assert_equal 'FAILURE Oops', response.message
  end

  def test_successful_verify
    response = stub_comms do
      @gateway.verify(@credit_card)
    end.respond_with(successful_authorize_response, successful_verify_response)
    assert_success response
  end

  def test_successful_verify_failed_void
    response = stub_comms do
      @gateway.verify(@credit_card, @options)
    end.respond_with(successful_authorize_response, failed_void_response)
    assert_success response
    assert_match %r{SUCCESS}, response.message
  end

  def test_unsuccessful_verify
    response = stub_comms do
      @gateway.verify(@credit_card, @options)
    end.respond_with(failed_authorize_response, successful_void_response)
    assert_failure response
    assert_not_nil response.message
  end


  def test_scrub
    assert @gateway.supports_scrubbing?
    assert_equal @gateway.scrub(pre_scrubbed), post_scrubbed
  end



  private

  def pre_scrubbed
    <<-PRE_SCRUBBED
      opening connection to sandbox.asgateway.com:80...
      opened
      <- "POST /api/auth HTTP/1.1\r\nContent-Type: application/x-www-form-urlencoded\r\nAccept-Encoding: gzip;q=1.0,deflate;q=0.6,identity;q=0.3\r\nAccept:\r\n*/*\r\nUser-Agent: Ruby\r\nConnection: close\r\nHost: sandbox.asgateway.com\r\nContent-Length: 330\r\n\r\n"
      <- "<?xml version=\"1.0\"?>\n<request>\n  <merchant>test-api</merchant>\n  <secret>c271ee995dd79671dc19f3ba4bb435e26bee68b0e831b7e9e4ae858c1584e0a33bc93b8d9ca3cedc</secret>\n  <action>purch</action>\n  <amount>100.00</amount>\n  <name>Longbob Longsen</name>\n  <number>4000100011112224</number>\n  <cv2>123</cv2>\n  <exp>092017</exp>\n</request>\n"
      -> "HTTP/1.1 200 OK \r\n"
      -> "Connection: close\r\n"
      -> "Content-Type: text/html;charset=utf-8\r\n"
      -> "Content-Length: 111\r\n"
      -> "X-Xss-Protection: 1; mode=block\r\n"
      -> "X-Content-Type-Options: nosniff\r\n"
      -> "X-Frame-Options: SAMEORIGIN\r\n"
      -> "Server: WEBrick/1.3.1 (Ruby/2.2.1/2015-02-26)\r\n"
      -> "Date: Sat, 17 Dec 2016 00:49:00 GMT\r\n"
      -> "Set-Cookie: rack.session=BAh7CEkiD3Nlc3Npb25faWQGOgZFVEkiRWY2ZjcxZGU2MjIxYTEwMGQ0NmZh%0ANDA3MGE4MjIwMjc2YmNiZTJjZDE1ZDFkOGU0MzA5MDE0NTZjMDI1Nzc2OTIG%0AOwBGSSIJY3NyZgY7AEZJIiU0OTI1MWE3Y2VhMGYzZmNiYzg5YWNhN2M4Y2Y3%0AN2MwZQY7AEZJIg10cmFja2luZwY7AEZ7B0kiFEhUVFBfVVNFUl9BR0VOVAY7%0AAFRJIi0xOGU0MGUxNDAxZWVmNjdlMWFlNjllZmFiMDlhZmI3MWY4N2ZmYjgx%0ABjsARkkiGUhUVFBfQUNDRVBUX0xBTkdVQUdFBjsAVEkiLWRhMzlhM2VlNWU2%0AYjRiMGQzMjU1YmZlZjk1NjAxODkwYWZkODA3MDkGOwBG%0A--569c961768f749348f8142d5e5d6780ceee80f70; path=/; HttpOnly\r\n"
      -> "Via: 1.1 vegur\r\n"
      -> "\r\n"
      reading 111 bytes...
      -> "<response><merchant>test-api</merchant><success>true</success><code></code><err></err><id>47548</id></response>"
      read 111 bytes
      Conn close
    PRE_SCRUBBED
  end

  def post_scrubbed
    <<-PRE_SCRUBBED
      opening connection to sandbox.asgateway.com:80...
      opened
      <- "POST /api/auth HTTP/1.1\r\nContent-Type: application/x-www-form-urlencoded\r\nAccept-Encoding: gzip;q=1.0,deflate;q=0.6,identity;q=0.3\r\nAccept:\r\n*/*\r\nUser-Agent: Ruby\r\nConnection: close\r\nHost: sandbox.asgateway.com\r\nContent-Length: 330\r\n\r\n"
      <- "<?xml version=\"1.0\"?>\n<request>\n  <merchant>[FILTERED]</merchant>\n  <secret>[FILTERED]</secret>\n  <action>purch</action>\n  <amount>100.00</amount>\n  <name>Longbob Longsen</name>\n  <number>[FILTERED]</number>\n  <cv2>[FILTERED]</cv2>\n  <exp>[FILTERED]</exp>\n</request>\n"
      -> "HTTP/1.1 200 OK \r\n"
      -> "Connection: close\r\n"
      -> "Content-Type: text/html;charset=utf-8\r\n"
      -> "Content-Length: 111\r\n"
      -> "X-Xss-Protection: 1; mode=block\r\n"
      -> "X-Content-Type-Options: nosniff\r\n"
      -> "X-Frame-Options: SAMEORIGIN\r\n"
      -> "Server: WEBrick/1.3.1 (Ruby/2.2.1/2015-02-26)\r\n"
      -> "Date: Sat, 17 Dec 2016 00:49:00 GMT\r\n"
      -> "Set-Cookie: rack.session=BAh7CEkiD3Nlc3Npb25faWQGOgZFVEkiRWY2ZjcxZGU2MjIxYTEwMGQ0NmZh%0ANDA3MGE4MjIwMjc2YmNiZTJjZDE1ZDFkOGU0MzA5MDE0NTZjMDI1Nzc2OTIG%0AOwBGSSIJY3NyZgY7AEZJIiU0OTI1MWE3Y2VhMGYzZmNiYzg5YWNhN2M4Y2Y3%0AN2MwZQY7AEZJIg10cmFja2luZwY7AEZ7B0kiFEhUVFBfVVNFUl9BR0VOVAY7%0AAFRJIi0xOGU0MGUxNDAxZWVmNjdlMWFlNjllZmFiMDlhZmI3MWY4N2ZmYjgx%0ABjsARkkiGUhUVFBfQUNDRVBUX0xBTkdVQUdFBjsAVEkiLWRhMzlhM2VlNWU2%0AYjRiMGQzMjU1YmZlZjk1NjAxODkwYWZkODA3MDkGOwBG%0A--569c961768f749348f8142d5e5d6780ceee80f70; path=/; HttpOnly\r\n"
      -> "Via: 1.1 vegur\r\n"
      -> "\r\n"
      reading 111 bytes...
      -> "<response><merchant>[FILTERED]</merchant><success>true</success><code></code><err></err><id>47548</id></response>"
      read 111 bytes
      Conn close
    PRE_SCRUBBED
  end

  def successful_purchase_response
    <<-eos
      <response>
        <merchant>test-api</merchant>
        <success>true</success>
        <code></code>
        <err></err>
        <id>47654</id>
      </response>
    eos
  end


  def failed_purchase_response
    <<-eos
      <response>
        <merchant>test-api</merchant>
        <success>false</success>
        <code>03</code>
        <err>number</err>
        <id>47655</id>
      </response>
    eos
  end

  def successful_authorize_response
    <<-eos
      <response>
        <merchant>test-api</merchant>
        <success>true</success>
        <code></code>
        <err></err>
        <id>47993</id>
      </response>
    eos
  end

  def failed_authorize_response
    <<-eos
      <response>
        <merchant>test-api</merchant>
        <success>false</success>
        <code>03</code>
        <err>number</err>
        <id>48095</id>
      </response>
    eos
  end

  def successful_capture_response
    <<-eos
      <response>
        <merchant>test-api</merchant>
        <success>true</success>
        <code></code>
        <err></err>
        <id>47994</id>
      </response>
    eos
  end

  def failed_capture_response
    <<-eos
      <h1>Oops</h1><p class=\"lead\">Wow, it would be so handy if we told you what went wrong here.</p>
    eos
  end

  def successful_refund_response
    <<-eos
      <response>
        <merchant>test-api</merchant>
        <success>true</success>
        <code></code>
        <err></err>
        <id>47655</id>
      </response>
    eos
  end

  def failed_refund_response
    <<-eos
      <h1>Oops</h1><p class=\"lead\">Wow, it would be so handy if we told you what went wrong here.</p>
    eos
  end

  def successful_void_response
    <<-eos
      <response>
        <merchant>test-api</merchant>
        <success>true</success>
        <code></code>
        <err></err>
        <id>47994</id>
      </response>
    eos
  end

  def failed_void_response
    <<-eos
      <h1>Oops</h1><p class=\"lead\">Wow, it would be so handy if we told you what went wrong here.</p>
    eos
  end

  def successful_verify_response
    <<-eos
      <response>
        <merchant>test-api</merchant>
        <success>true</success>
        <code></code>
        <err></err>
        <id>47994</id>
      </response>
    eos
  end

  def failed_verify_response
    <<-eos
      <response>
        <merchant>test-api</merchant>
        <success>false</success>
        <code>03</code>
        <err>number</err>
        <id>48483</id>
      </response>
    eos
  end
end
