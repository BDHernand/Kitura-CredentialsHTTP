/**
 * Copyright IBM Corporation 2016
 *
 * Licensed under the Apache License, Version 2.0 (the "License");
 * you may not use this file except in compliance with the License.
 * You may obtain a copy of the License at
 *
 * http://www.apache.org/licenses/LICENSE-2.0
 *
 * Unless required by applicable law or agreed to in writing, software
 * distributed under the License is distributed on an "AS IS" BASIS,
 * WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
 * See the License for the specific language governing permissions and
 * limitations under the License.
 **/

import Foundation
import XCTest

import Kitura
import KituraNet
import KituraSys
import Credentials

@testable import CredentialsHttp

class TestBasic : XCTestCase {
    
    static var allTests : [(String, TestBasic -> () throws -> Void)] {
        return [
                   ("testNoCredentials", testNoCredentials),
                   ("testBadCredentials", testBadCredentials),
                   ("testBasic", testBasic),
        ]
    }
    
    override func tearDown() {
        doTearDown()
    }
    
    let host = "127.0.0.1"
    
    let router = TestBasic.setupRouter()
    
    func testNoCredentials() {
        performServerTest(router: router) { expectation in
            self.performRequest(method: "get", host: self.host, path: "/private/api/data", callback: {response in
                XCTAssertNotNil(response, "ERROR!!! ClientRequest response object was nil")
                XCTAssertEqual(response!.statusCode, HTTPStatusCode.unauthorized, "HTTP Status code was \(response!.statusCode)")
                XCTAssertEqual(response!.headers["WWW-Authenticate"]!.first!, "Basic realm=\"test\"")
                expectation.fulfill()
            })
        }
    }
    
    func testBadCredentials() {
        performServerTest(router: router) { expectation in
            self.performRequest(method: "get", path:"/private/api/data", callback: {response in
                XCTAssertNotNil(response, "ERROR!!! ClientRequest response object was nil")
                XCTAssertEqual(response!.statusCode, HTTPStatusCode.unauthorized, "HTTP Status code was \(response!.statusCode)")
                XCTAssertEqual(response!.headers["WWW-Authenticate"]!.first!, "Basic realm=\"test\"")
                expectation.fulfill()
                }, headers: ["Authorization" : "Basic QWxhZGRpbjpPcGVuU2VzYW1l"])
        }
    }

    func testBasic() {
        performServerTest(router: router) { expectation in
            self.performRequest(method: "get", path:"/private/api/data", callback: {response in
                XCTAssertNotNil(response, "ERROR!!! ClientRequest response object was nil")
                XCTAssertEqual(response!.statusCode, HTTPStatusCode.OK, "HTTP Status code was \(response!.statusCode)")
                do {
                    let body = try response!.readString()
                    XCTAssertEqual(body!,"<!DOCTYPE html><html><body><b>Mary is logged in with HttpBasic</b></body></html>\n\n")
                }
                catch{
                    XCTFail("No response body")
                }
                expectation.fulfill()
            }, headers: ["Authorization" : "Basic TWFyeTpxd2VyYXNkZg=="])
        }
    }

    static func setupRouter() -> Router {
        let router = Router()
        
        let apiCredentials = Credentials()
        let users = ["John" : "12345", "Mary" : "qwerasdf"]
        let basicCredentials = CredentialsHttpBasic(userProfileLoader: { userId, callback in
            if let storedPassword = users[userId] {
                callback(userProfile: UserProfile(id: userId, displayName: userId, provider: "HttpBasic"), password: storedPassword)
            }
            else {
                callback(userProfile: nil, password: nil)
            }
        }, realm: "test")
        apiCredentials.register(plugin: basicCredentials)

        let digestCredentials = CredentialsHttpDigest(userProfileLoader: { userId, callback in
            if let storedPassword = users[userId] {
                callback(userProfile: UserProfile(id: userId, displayName: userId, provider: "HttpDigest"), password: storedPassword)
            }
            else {
                callback(userProfile: nil, password: nil)
            }
            }, realm: "Kitura-users", opaque: "0a0b0c0d")
        
        apiCredentials.register(plugin: digestCredentials)

        router.all("/private/*", middleware: BodyParser())
        router.all("/private/api", middleware: apiCredentials)
        router.get("/private/api/data", handler:
            { request, response, next in
                response.headers["Content-Type"] = "text/html; charset=utf-8"
                do {
                    if let profile = request.userProfile  {
                        try response.status(.OK).end("<!DOCTYPE html><html><body><b>\(profile.displayName) is logged in with \(profile.provider)</b></body></html>\n\n")
                        next()
                        return
                    }
                    else {
                        try response.status(.unauthorized).end()
                    }
                }
                catch {}
                next()
        })

        router.error { request, response, next in
            response.headers["Content-Type"] = "text/html; charset=utf-8"
            do {
                let errorDescription: String
                if let error = response.error {
                    errorDescription = "\(error)"
                }
                else {
                    errorDescription = ""
                }
                try response.send("Caught the error: \(errorDescription)").end()
            }
            catch {}
            next()
        }
        
        return router
    }
}