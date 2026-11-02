import Foundation
import SQLite3
typealias ContentPart=String
struct RawMessage {
    enum Role: String { case user, assistant }
    let id: String; let sessionId: String; let role: Role; let parts: [String]
}
actor ChatStore {
    var db: OpaquePointer?
    init() {
        var handle: OpaquePointer?
        precondition(sqlite3_open(":memory:", &handle) == SQLITE_OK)
        db = handle
        precondition(sqlite3_exec(handle, "CREATE TABLE messages (id TEXT PRIMARY KEY, session_id TEXT, role TEXT, parts_json TEXT)", nil, nil, nil) == SQLITE_OK)
    }
    deinit { sqlite3_close(db) }
    func bindOptionalText(_ stmt: OpaquePointer?, index: Int32, value: String?) {
        if let value { sqlite3_bind_text(stmt, index, value, -1, unsafeBitCast(-1, to: sqlite3_destructor_type.self)) }
        else { sqlite3_bind_null(stmt,index) }
    }
    func seed() { precondition(sqlite3_exec(db, "INSERT INTO messages VALUES ('answer','commander','assistant','[\"saved answer\"]')",nil,nil,nil)==SQLITE_OK) }
}
@main struct BotDeliveryPersistenceTests {
    static func main() async {
        let db = ChatStore(); await db.seed()
        let good = RawMessage(id:"answer",sessionId:"commander",role:.assistant,parts:["saved answer"])
        let found = await db.containsPersistedMessage(good); precondition(found)
        for wrong in [RawMessage(id:"missing",sessionId:"commander",role:.assistant,parts:good.parts),
                      RawMessage(id:"answer",sessionId:"other",role:.assistant,parts:good.parts),
                      RawMessage(id:"answer",sessionId:"commander",role:.user,parts:good.parts),
                      RawMessage(id:"answer",sessionId:"commander",role:.assistant,parts:["not saved"])] {
            let found = await db.containsPersistedMessage(wrong); precondition(!found)
        }
        typealias R = BotConversationMessageCounter.Row
        let user = R(assistant:false,visible:true,internalRow:false,callback:false)
        let answer = R(assistant:true,visible:true,internalRow:false,callback:false)
        let tool = R(assistant:false,visible:false,internalRow:false,callback:false)
        let thinking = R(assistant:true,visible:false,internalRow:false,callback:false)
        let reminder = R(assistant:false,visible:true,internalRow:true,callback:false)
        let callback = R(assistant:false,visible:true,internalRow:false,callback:true)
        precondition(BotConversationMessageCounter.count([user,thinking,tool,answer,tool,answer,reminder,answer])==2)
        precondition(BotConversationMessageCounter.count([user,answer,callback,answer,user,answer])==5)
        precondition(BotConversationMessageCounter.count([thinking,tool,reminder])==0)
        print("PASS: actual SQLite delivery confirmation rejects absent/stale/wrong-session/role writes; logical count excludes tools, thought, reminders and callbacks and merges assistant continuations")
    }
}
