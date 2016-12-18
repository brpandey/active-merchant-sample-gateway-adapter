# Active Merchant Sample Gateway Adapter

## Here's a work sample from an interview, that I wrote to implement a ruby "adapter" to issue xml requests to rest endpoints under the domain of credit card processing

The adapter file is here -> 
    lib/active_merchant/billing/gateways/awesome_sauce.rb
and test files are here -> 
    test/unit/gateways/awesome_sauce_test.rb
    test/remote/gateways/remote_awesome_sauce_test.rb

Following the new gateway contribution guidelines of the ActiveMerchant project, this is a sample new gateway adapter and tests for a mythical "Awesomesauce Gateway" that has been setup and has documentation for.

See here: [ActiveMerchant Contribution](https://github.com/activemerchant/active_merchant/wiki/contributing)

Here is the behavior that needs to be implemented!


## Awesomesauce Documentation
Awesomesauce is the #1 most buzzword compliant gateway in the industry! You will love this sauce, it's awesome!
Here at Awesomesauce, we think REST is the best thing since sliced bread, even though we don't really understand
it. So we're declaring our API to be REST-compliant; we hope you're OK with that... actually we don't really care.

### Authentication
To authenticate a request, add your API login and key to it:
    <request>
    <merchant>[login]</merchant>
    <secret>[key]</secret>
    ...
    </request>

Production requests should be made by POST ing to: https://prod.awesomesauce.example.com/

### Authorizing a purchase
To authorize the eventual capture of funds, use the auth endpoint:

POST to /api/auth
    <request>
    login info
    <action>auth</action>
    <amount>100.00</amount>
    <name>Bob</name>
    <number>CC num</number>
    <cv2>CVC num</number>
    <exp>012011</exp>
    </request>

If you want to immediately collect the funds, use an action of purch :
    <action>purch</action>

The response will have the following fields:
Field- Explanation
success - true or false
err - a message about what happened
code - a code about what happened
id - a reference for the operation




### Capturing
If you auth , then you have to capture in order to actually collect the funds. Do that by passing an action of
capture to /api/ref , and including the id from the auth :

POST to /api/ref
    <request>
    login info
    <action>capture</action>
    <ref>id</ref>
    </request>

### Cancel
Void an auth or refund a purchase by passing the id to ref with an action of cancel :

POST to /api/ref
    <request>
    login info
    <action>cancel</action>
    <ref>id</ref>
    </request>

Testing

To test, sign up for a sandbox account (http://sandbox.asgateway.com/) and send all API requests to
http://sandbox.asgateway.com/.
All amounts with cents of .00 will succeed, and any other amount of cents will trigger the corresponding error
code.

You can use any valid test credit card number for testing.

Error codes
CodeError
* 01 Should never happen
* 02 Missing field
* 03 Bad format
* 04 Bad number
* 05 Arrest them!
* 06 Expired
* 07 Bad ref


Some one off misc and testing

    $ source ~/.rvm/scripts/rvm 
    $ rvm use 2.2.4

    curl -X POST -d @purchase_request_1.xml http://sandbox.asgateway.com/api/auth
    <response><merchant>test-api</merchant><success>true</success><code></code><err></err><id>46221</id></response>


purchase_request_1.xml:

    <request><merchant>test-api</merchant><secret>c271ee995dd79671dc19f3ba4bb435e26bee68b0e831b7e9e4ae858c1584e0a33bc93b8d9ca3cedc</secret><action>purch</action><amount>1.00</amount><name>Longbob Longsen</name><number>4242424242424242</number><cv2>123</cv2><exp>092017</exp></request>
