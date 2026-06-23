    func syncService(_ service: SyncService, didReceiveTombstones deletedIds: [String]) {
        guard let db = db else { return }
        do {
            try db.transaction {
                for entryId in deletedIds { 
                    let idLower = entryId.lowercased()
                    try db.run(entriesTable.filter(id == idLower).delete()) 
                    try db.run(tombstonesTable.insert(or: .replace, tombstoneId <- idLower, tombstoneTimestamp <- Date()))
                }
            }
            try loadData()
            refreshUI()
        } catch { }
    }