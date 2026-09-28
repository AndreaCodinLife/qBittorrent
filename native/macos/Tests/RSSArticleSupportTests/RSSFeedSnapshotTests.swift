import Foundation
import Testing
@testable import RSSArticleSupport

struct RSSFeedSnapshotTests {
    @Test func parsesFeedsAndNestedFoldersFromOneResponse() throws {
        let data = Data(
            #"""
            {
              "Top Feed": {
                "uid": "top-id",
                "url": "https://top.example/rss.xml",
                "title": "",
                "articles": []
              },
              "News": {
                "Tech": {
                  "Science Feed": {
                    "uid": "science-id",
                    "url": "https://science.example/rss.xml",
                    "title": "  Science Daily  ",
                    "refreshInterval": 900,
                    "isLoading": true,
                    "hasError": false,
                    "articles": [
                      {
                        "id": "article-1",
                        "title": "New launch",
                        "author": "A. Reporter",
                        "description": "Article body",
                        "link": "https://science.example/story",
                        "torrentURL": "magnet:?xt=urn:btih:abc",
                        "date": "Tue, 29 Sep 2026 09:30:00 +0000",
                        "isRead": false
                      }
                    ]
                  }
                },
                "Empty Folder": {}
              }
            }
            """#.utf8
        )

        let snapshot = try RSSFeedSnapshotParser.parse(data)
        let feedsByPath = Dictionary(uniqueKeysWithValues: snapshot.feeds.map { ($0.path, $0) })
        let article = try #require(feedsByPath["News\\Tech\\Science Feed"]?.articles.first)

        #expect(snapshot.feeds.count == 2)
        #expect(feedsByPath["Top Feed"]?.title == "Top Feed")
        #expect(feedsByPath["News\\Tech\\Science Feed"]?.title == "Science Daily")
        #expect(feedsByPath["News\\Tech\\Science Feed"]?.refreshInterval == 900)
        #expect(feedsByPath["News\\Tech\\Science Feed"]?.isLoading == true)
        #expect(snapshot.folders.map(\.path) == ["News", "News\\Empty Folder", "News\\Tech"])
        #expect(article.selectionID == "News\\Tech\\Science Feed\u{1F}article-1")
        #expect(article.title == "New launch")
        #expect(article.author == "A. Reporter")
        #expect(article.torrentURL == "magnet:?xt=urn:btih:abc")
        #expect(article.dateValue != nil)
        #expect(!article.isRead)
    }

    @Test func rejectsNonObjectResponses() {
        var didThrow = false
        do {
            _ = try RSSFeedSnapshotParser.parse(Data("[]".utf8))
        } catch {
            didThrow = true
        }
        #expect(didThrow)
    }
}
