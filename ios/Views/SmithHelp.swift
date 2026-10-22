import SwiftUI

// Smith: the built-in help guide. Rule-based and offline; nothing typed here leaves the phone.
// The question bank is shared with the desktop and Android apps (generated from their help engine).

enum SmithConfig {
    static let edition = "std"
}

struct SmithEntry: Decodable, Identifiable {
    let id: String
    let q: [String]
    let more: [String]
    let a: String
}

private struct SmithBank: Decodable {
    let std: [SmithEntry]
    let pro: [SmithEntry]
    let syn: [String: String]
    let stop: [String]
}

enum SmithEngine {
    private static let bank: SmithBank = {
        let data = Data(rawBank.utf8)
        return (try? JSONDecoder().decode(SmithBank.self, from: data)) ?? SmithBank(std: [], pro: [], syn: [:], stop: [])
    }()

    static var entries: [SmithEntry] { SmithConfig.edition == "std" ? bank.std : bank.pro }

    private static let stopWords = Set(bank.stop)

    private static func norm(_ raw: String) -> String {
        var w = raw.lowercased().filter { $0.isLetter || $0.isNumber || $0 == "'" || $0 == "-" }
        if let s = bank.syn[w] { w = s }
        if w.count > 4 {
            for suffix in ["ing", "ed", "es", "s"] where w.hasSuffix(suffix) { w = String(w.dropLast(suffix.count)); break }
        }
        return bank.syn[w] ?? w
    }

    static func tokens(_ s: String) -> [String] {
        s.split(whereSeparator: { $0.isWhitespace }).map { norm(String($0)) }.filter { !$0.isEmpty && !stopWords.contains($0) }
    }

    private static func lev(_ a: [Character], _ b: [Character]) -> Int {
        if abs(a.count - b.count) > 2 { return 9 }
        var prev = Array(0...b.count)
        for i in 1...max(a.count, 1) where !a.isEmpty {
            var cur = [i] + Array(repeating: 0, count: b.count)
            if b.isEmpty { prev = cur; continue }
            for j in 1...b.count {
                cur[j] = min(prev[j] + 1, cur[j - 1] + 1, prev[j - 1] + (a[i - 1] == b[j - 1] ? 0 : 1))
            }
            prev = cur
        }
        return prev[b.count]
    }

    private static func same(_ a: String, _ b: String) -> Bool {
        if a == b { return true }
        let ca = Array(a), cb = Array(b)
        if ca.count >= 5 && cb.count >= 5 && lev(ca, cb) <= 1 { return true }
        return ca.count >= 8 && cb.count >= 8 && lev(ca, cb) <= 2
    }

    private struct Doc {
        let entry: SmithEntry
        let sets: [[String]]
        let flat: [String]
    }

    private static let docs: [Doc] = entries.map { e in
        let sets = e.q.map { tokens($0) }
        var flat: [String] = []
        for t in sets.flatMap({ $0 }) + tokens(e.id.replacingOccurrences(of: "-", with: " ")) where !flat.contains(t) { flat.append(t) }
        return Doc(entry: e, sets: sets, flat: flat)
    }

    private static let df: [String: Int] = {
        var m: [String: Int] = [:]
        for d in docs { for t in Set(d.flat) { m[t, default: 0] += 1 } }
        return m
    }()

    private static func idf(_ t: String) -> Double { log(1 + Double(docs.count) / (1 + Double(df[t] ?? 0))) }

    /// Standard edition: Pro-only topics are not offered as suggestions unless the user asked about Pro.
    static func isProTopic(_ e: SmithEntry) -> Bool {
        SmithConfig.edition == "std" && e.a.hasPrefix("That is a Vaultinator Pro feature")
    }

    static func visible(_ list: [SmithEntry], askedAbout: SmithEntry?) -> [SmithEntry] {
        if let a = askedAbout, isProTopic(a) { return list }
        return list.filter { !isProTopic($0) }
    }

    struct Result {
        let match: SmithEntry?
        let alternatives: [SmithEntry]
    }

    static func answer(_ question: String) -> Result {
        let qt = tokens(question)
        guard !qt.isEmpty else { return Result(match: nil, alternatives: []) }
        let qTotal = qt.reduce(0.0) { $0 + idf($1) }
        let scored: [(SmithEntry, Double)] = docs.map { d in
            var best = 0.0
            for set in d.sets where !set.isEmpty {
                var hit = 0.0, tot = 0.0
                for t in set { let w = idf(t); tot += w; if qt.contains(where: { same($0, t) }) { hit += w } }
                var qhit = 0.0, qtot = 0.0
                for x in qt { let w = idf(x); qtot += w; if set.contains(where: { same(x, $0) }) { qhit += w } }
                let s = (hit / tot) * 0.45 + (qhit / qtot) * 0.55
                best = max(best, s)
            }
            var bag = 0.0
            for x in qt where d.flat.contains(where: { same(x, $0) }) { bag += idf(x) }
            return (d.entry, max(best, (bag / qTotal) * 0.8))
        }.sorted { $0.1 > $1.1 }
        guard let top = scored.first else { return Result(match: nil, alternatives: []) }
        let ok = top.1 >= 0.5
        var pool = scored.dropFirst(ok ? 1 : 0).filter { $0.1 >= 0.3 }.map { $0.0 }
        if ok {
            let mo = top.0.more.compactMap { id in entries.first { $0.id == id } }
            pool = mo + pool.filter { p in !mo.contains { $0.id == p.id } }
        }
        let alts = visible(pool, askedAbout: ok ? top.0 : nil).prefix(3)
        return Result(match: ok ? top.0 : nil, alternatives: Array(alts))
    }

    private static let rawBank = #"""
{"std":[{"id":"what","q":["what is vaultinator","what does this app do","what is this","who made this app","about the app"],"more":[],"a":"Vaultinator is a password manager. It keeps your logins, notes and cards in one encrypted vault that only your master password opens. It works on your computer and your phone, and nothing is stored in the cloud."},{"id":"create-vault","q":["how do i create a vault","set up my vault","first time setup","make a new vault","get started","i just installed it what now","new account"],"more":[],"a":"On the first screen choose Create Vault, type a master password twice and tap Create Vault. The strength meter shows how tough it is. Pick something long you can remember, like four random words."},{"id":"master-password","q":["what is the master password","which password do i use to unlock","master pass","what should my master password be","good master password"],"more":[],"a":"The master password is the one password you remember. It unlocks everything else. Make it long (a phrase of 4+ random words works well) and never reuse it anywhere."},{"id":"forgot-master","q":["i forgot my master password","forgot password","cant unlock vault","reset master password","lost my password","locked out","can you reset my password","password recovery","cant remember my master password","i dont remember my master password","what if i forget my master password"],"more":["recovery"],"a":"There is no reset. Nobody at Vaultinator can open your vault, not even us, and this edition has no recovery phrase. If you forget the master password the vault cannot be opened, which is what keeps it safe from everyone else. If you have an export or a synced device that is still unlocked, you can copy your data from there into a new vault."},{"id":"unlock-wrong","q":["it says wrong password","incorrect password","wont unlock","unlock not working","master password not working","caps lock"],"more":["forgot-master","unlock-photo"],"a":"Check caps lock, then tap SHOW next to the field to see what you are typing. If you are sure it is right, make sure you are on the right vault (each device has its own). After a wrong try the app can take an unlock photo if you turned that on."},{"id":"lock","q":["how do i lock the vault","lock app","log out","sign out","close the vault"],"more":[],"a":"Tap the lock icon at the top right. The vault also locks by itself after the time you pick in Preferences."},{"id":"autolock","q":["auto lock","vault locks by itself","how long until it locks","change lock time","stop it locking","locks too fast","never lock","make the vault lock quicker","make it lock sooner","lock after less time"],"more":[],"a":"Open Preferences, then Security, then \"Auto-lock vault after\". Choose 1, 5, 15 or 30 minutes, or Never. Shorter is safer."},{"id":"add-entry","q":["how do i add a password","save a new login","add entry","new password","store a password","create entry","add account"],"more":[],"a":"Tap Add Entry at the top right. Fill in a title, username and password (use Generate for a strong one), add the website if you like, then Save Entry."},{"id":"edit-entry","q":["how do i edit a password","change a saved password","update an entry","edit entry","rename an entry","fix a typo in an entry"],"more":[],"a":"Tap the entry to open it, change what you need and tap Save."},{"id":"delete-entry","q":["how do i delete a password","remove an entry","delete entry","get rid of a login","delete several","delete multiple entries","bulk delete"],"more":[],"a":"Open the entry and tap Delete. To remove several at once, tick the boxes on the left of each row, then tap Delete Selected. Deleting cannot be undone, so export a backup first if unsure."},{"id":"copy","q":["how do i copy a password","copy username","copy to clipboard","copy without showing","paste my password"],"more":[],"a":"Each row has copy buttons for the username and password, so you never have to show them. The clipboard is cleared automatically after the time set in Preferences."},{"id":"show-password","q":["show password","reveal password","see my password","view password","what is my saved password"],"more":[],"a":"Open the entry and tap the eye to reveal the password. It hides again when you close it."},{"id":"clipboard-clear","q":["clipboard","clear clipboard","copied password stays","how long does copy last","clipboard timer"],"more":[],"a":"Preferences, Security, \"Clear clipboard after copying\": 30 seconds, 1 minute or 2 minutes. After that the copied password is wiped."},{"id":"favorites","q":["favorites","favourite","star an entry","pin to top","quick access entries","mark as favorite"],"more":[],"a":"Tap the star on an entry, or tick \"Add to favorites\" when creating it. The Favorites list on the left shows only those."},{"id":"search","q":["how do i find an entry","search","cant find my password","look up a login","find a password"],"more":[],"a":"Type in the search box at the top. It filters by title and username as you type."},{"id":"categories","q":["categories","folders","organize my passwords","how do i group entries","add a category","create a folder","sort my logins"],"more":[],"a":"Use Add Category in the left sidebar. Give it a name, icon and color, then choose it on any entry. Click a category to see only its entries."},{"id":"nested-folders","q":["folder inside a folder","subfolder","nested folders","move a folder","put a category inside another"],"more":[],"a":"That is a Vaultinator Pro feature, so it is not in this app. Vaultinator Pro is a separate edition with extra tools. Ask me what Pro adds if you are curious."},{"id":"delete-category","q":["delete a category","remove a folder","what happens to entries when i delete a category"],"more":[],"a":"Hover the category and tap the delete icon. Your entries are not deleted, they just become uncategorized."},{"id":"notes","q":["secure note","store notes","private notes","where do i put text","save a note"],"more":[],"a":"Every entry has a Notes box that is encrypted like the password."},{"id":"url","q":["website link","open the website","url field","login page link"],"more":[],"a":"Add the website in the Website URL field. It shows on the entry so you can find the right login page quickly."},{"id":"generator","q":["generate a password","password generator","make a strong password","random password","create a password for me","suggest a password"],"more":[],"a":"Tap Generate when adding an entry, or the wand icon at the top. Drag the length, tick which character types to include (A-Z, a-z, 0-9, symbols) and tap Regenerate until you like it, then copy it."},{"id":"passphrase","q":["passphrase","words password","easy to remember password","memorable password","diceware"],"more":[],"a":"That is a Vaultinator Pro feature, so it is not in this app. Vaultinator Pro is a separate edition with extra tools. Ask me what Pro adds if you are curious."},{"id":"generator-history","q":["i lost the password i generated","generator history","recently used passwords","previous generated passwords"],"more":[],"a":"That is a Vaultinator Pro feature, so it is not in this app. Vaultinator Pro is a separate edition with extra tools. Ask me what Pro adds if you are curious."},{"id":"lookalike","q":["confusing characters","o and 0","look alike characters","password hard to read"],"more":[],"a":"That is a Vaultinator Pro feature, so it is not in this app. Vaultinator Pro is a separate edition with extra tools. Ask me what Pro adds if you are curious."},{"id":"strength","q":["password strength","is my password strong","what do the colors mean","entropy","how strong is it"],"more":[],"a":"The strength meter on the Create Vault screen shows how hard your master password is to guess. Longer beats fancier: a phrase of 4+ random words is strong."},{"id":"totp","q":["two factor codes","2fa","authenticator","one time code","totp","google authenticator replacement","six digit code","authenticator key","otp"],"more":[],"a":"That is a Vaultinator Pro feature, so it is not in this app. Vaultinator Pro is a separate edition with extra tools. Ask me what Pro adds if you are curious."},{"id":"totp-wrong","q":["authenticator code is wrong","code not working","2fa code invalid","totp not accepted","code expired","authenticator code isnt working","my 2fa codes are wrong"],"more":[],"a":"That is a Vaultinator Pro feature, so it is not in this app. Vaultinator Pro is a separate edition with extra tools. Ask me what Pro adds if you are curious."},{"id":"import","q":["import passwords","move from another password manager","bring my passwords from chrome","import csv","switch from lastpass","import from bitwarden","import from 1password","import from keeper","transfer passwords"],"more":[],"a":"Export a CSV from your old manager or browser, then tap the import icon in Vaultinator and pick the file. The format is detected automatically. Delete the CSV afterwards, since it is not encrypted."},{"id":"export","q":["export passwords","backup my vault","download my passwords","save a copy","export csv","back up"],"more":[],"a":"Tap the export icon and choose CSV (opens in other password managers) or a JSON backup. Exports are readable by anyone, so keep them somewhere safe and delete them when done."},{"id":"import-failed","q":["import failed","import not working","import says error","some passwords did not import","import missing entries"],"more":[],"a":"Make sure the file ends in .csv or .json and came straight from the other app without being edited in a spreadsheet that changed the columns. If it still fails, send us the name of the app it came from with the message button."},{"id":"sync","q":["sync with my phone","sync devices","connect phone to computer","use on two devices","transfer to my phone","sync with ios","sync with android","start sync","how does sync work","how do i sync","get sync working"],"more":["sync-subnet","sync-fails"],"a":"There are a few ways to get sync working. They all start on the computer: Preferences, Sync, Start Sync.\n1) Generate QR (easiest): tap Generate QR on the computer, then scan it from the phone app.\n2) Manual entry: if the QR will not scan, type the connection string shown under it into the phone app.\n3) Automatic: with both devices on the same Wi-Fi and matching network settings (same subnet), they should find each other on their own.\nSync goes straight between your own devices with no cloud, and it is in beta. Want more info, like how to check your subnet?"},{"id":"sync-subnet","q":["check subnet","what is my subnet","same network check","how to check network settings","find my ip address","subnet mask","same wifi check","are we on the same network"],"more":["sync-fails"],"a":"Both devices need to be on the same network and subnet. Windows: open Command Prompt, run ipconfig, and read IPv4 Address and Subnet Mask. iPhone: Settings, Wi-Fi, tap the (i) next to your network and read IP Address and Subnet Mask. Android: Settings, Wi-Fi, tap your network, then Advanced or View more for the IP address. Mac: System Settings, Wi-Fi, Details, TCP/IP. The first three numbers of the IP address (like 192.168.1) should match on both devices. Guest networks and VPNs often break this."},{"id":"sync-fails","q":["sync not working","phone wont connect","qr code not scanning","sync failed","cant connect to desktop","sync stuck","devices not syncing"],"more":[],"a":"Check both devices are on the same Wi-Fi (not guest or mobile data), that the computer app is open and unlocked, and that Start Sync is on. If the QR will not scan, type the connection string shown under it. A firewall prompt on the computer must be allowed."},{"id":"cloud","q":["is it in the cloud","cloud backup","online account","do you store my data","where is my data stored","server","sync across the internet","access from anywhere"],"more":[],"a":"No cloud. Your vault is an encrypted file on each of your devices. We have no server holding it. Device sync happens directly between your devices on the same network."},{"id":"new-phone","q":["new phone","i got a new device","move to a new phone","lost my phone","replace device","transfer vault"],"more":[],"a":"On the old device export a backup (or sync to the new one while both are on the same Wi-Fi). On the new device create or open a vault and import the backup. If the old device is gone and you never backed up or synced, the vault cannot be recovered."},{"id":"security","q":["is it safe","how secure is this","encryption","who can see my passwords","is it encrypted","can you see my passwords","zero knowledge","privacy"],"more":[],"a":"Everything is encrypted on your device with a key made from your master password. We never see your passwords, we cannot reset them, and the app makes no accounts and calls no servers. Device sync, if you use it, goes directly between your own devices on your network."},{"id":"breach","q":["has my password been leaked","breach check","pwned","have i been pwned","data breach","compromised passwords"],"more":["audit"],"a":"That is a Vaultinator Pro feature, so it is not in this app. Vaultinator Pro is a separate edition with extra tools. Ask me what Pro adds if you are curious."},{"id":"audit","q":["security audit","weak passwords","reused passwords","old passwords","check my vault health","which passwords are bad","security score"],"more":[],"a":"That is a Vaultinator Pro feature, so it is not in this app. Vaultinator Pro is a separate edition with extra tools. Ask me what Pro adds if you are curious."},{"id":"unlock-photo","q":["unlock photo","photo of intruder","camera after wrong password","who tried to unlock","wrong password picture"],"more":[],"a":"In Preferences turn on Unlock photo. After a wrong password the front camera takes a picture stamped with date, time and location. View unlock photos shows them, and you can delete any."},{"id":"screenshot","q":["can others see my screen","screenshots","screen recording protection"],"more":[],"a":"Passwords stay hidden until you reveal them and hide again afterwards. Be careful revealing them while screen sharing."},{"id":"hacked","q":["i think i was hacked","someone has my passwords","device stolen","phone was stolen","laptop stolen","what do i do if my device is lost","someone stole my laptop","someone stole my phone","my phone got stolen"],"more":[],"a":"Your vault is encrypted and locked, so a thief needs your master password. Still, change the passwords for your most important accounts (email, bank) from another device, and if you sync to other devices, treat the lost one as compromised until you have changed them."},{"id":"pro-what","q":["what is pro","pro features","pro vs standard","difference between pro and regular","what do i get with pro","upgrade","how much is pro","what does pro include","price","is pro free"],"more":[],"a":"Vaultinator Pro is a separate edition with extra features such as card and passport records, file attachments, a recovery phrase, secure sharing and a security audit. This is the standard edition, which covers logins, notes, categories, the generator, import, export and device sync."},{"id":"pro-turn-on","q":["how do i turn on pro","enable pro","activate pro","unlock pro features","where is the pro switch","pro is locked"],"more":[],"a":"That is a Vaultinator Pro feature, so it is not in this app. Vaultinator Pro is a separate edition with extra tools. Ask me what Pro adds if you are curious."},{"id":"record-types","q":["credit card","store a card","payment card","bank account","passport","drivers license","wifi password","ssh key","record types","identity","server login","software license","what can i store"],"more":[],"a":"That is a Vaultinator Pro feature, so it is not in this app. Vaultinator Pro is a separate edition with extra tools. Ask me what Pro adds if you are curious."},{"id":"custom-fields","q":["custom field","add my own field","security question","extra field","pin field","secret field"],"more":[],"a":"That is a Vaultinator Pro feature, so it is not in this app. Vaultinator Pro is a separate edition with extra tools. Ask me what Pro adds if you are curious."},{"id":"attachments","q":["attach a file","attachments","store a pdf","upload a document","file size limit","save a photo of my passport","add files"],"more":[],"a":"That is a Vaultinator Pro feature, so it is not in this app. Vaultinator Pro is a separate edition with extra tools. Ask me what Pro adds if you are curious."},{"id":"voice-notes","q":["voice note","record audio","audio note","record a voice memo","store audio","play audio","photo preview","view a photo","store pictures","add a picture","save an image","open a pdf","read a word document","view a docx","markdown file","read a pdf","document viewer"],"more":[],"a":"That is a Vaultinator Pro feature, so it is not in this app. Vaultinator Pro is a separate edition with extra tools. Ask me what Pro adds if you are curious."},{"id":"history","q":["old password","password history","previous versions","undo a change","i overwrote my password","see earlier values"],"more":[],"a":"That is a Vaultinator Pro feature, so it is not in this app. Vaultinator Pro is a separate edition with extra tools. Ask me what Pro adds if you are curious."},{"id":"recovery","q":["recovery phrase","recovery words","twelve words","12 words","backup phrase","set up recovery","emergency sheet"],"more":[],"a":"That is a Vaultinator Pro feature, so it is not in this app. Vaultinator Pro is a separate edition with extra tools. Ask me what Pro adds if you are curious."},{"id":"share","q":["share a password","send a login to someone","share with family","share file","send entries to another person","give access to my wife"],"more":[],"a":"That is a Vaultinator Pro feature, so it is not in this app. Vaultinator Pro is a separate edition with extra tools. Ask me what Pro adds if you are curious."},{"id":"expiry","q":["expiry date","expiring","remind me when my passport expires","renewal reminder","license expires","card expiry"],"more":[],"a":"That is a Vaultinator Pro feature, so it is not in this app. Vaultinator Pro is a separate edition with extra tools. Ask me what Pro adds if you are curious."},{"id":"themes","q":["change theme","dark mode","light mode","colors","appearance","change the look","terminal theme"],"more":[],"a":"Preferences, Appearance, Theme. Choose Brass, Layer, Terminal or Midnight."},{"id":"sound","q":["sound","lock sound","turn off sound","turn on sound","splash sound","noise when opening"],"more":[],"a":"The lock sound on the splash screen is off by default. Turn it on in Preferences, Sound."},{"id":"smith","q":["who is smith","what is smith","who are you","what are you","are you ai","are you a robot","are you real","are you chatgpt"],"more":[],"a":"I am Smith, the lock with opinions. I am a built-in guide, not a smart AI. I know every button in this app, I can point at them, and if I do not know the answer I will pass your question to the professionals."},{"id":"version","q":["what version","app version","beta","is this finished","known issues"],"more":[],"a":"This is Vaultinator 1.0.0 beta. It works, but expect rough edges, especially device sync. Please report anything odd with the message button."},{"id":"autofill","q":["autofill","browser extension","fill passwords in chrome","auto login","fill in apps","passkeys","face id","fingerprint","biometric"],"more":[],"a":"Not yet. Today you copy the username and password from Vaultinator and paste them in. Browser extension, phone autofill, biometric unlock and passkeys are not built yet. Tell the team if you want them sooner."},{"id":"languages","q":["other languages","spanish","translate the app","change language"],"more":[],"a":"The app is English only for now. Other languages are planned."},{"id":"delete-vault","q":["delete my vault","start over","erase everything","uninstall","remove the app"],"more":[],"a":"Uninstalling removes the app, but the encrypted vault file may stay on the device. Export a backup first if you might need your data. We cannot delete your data remotely because we never have it."},{"id":"two-vaults","q":["multiple vaults","second vault","separate vault for work","two vaults","family vault"],"more":[],"a":"One vault per device for now. Use categories to keep work and personal apart, or use Pro sharing to hand specific entries to another person."},{"id":"app-crash","q":["app crashed","app is frozen","white screen","not responding","app wont open","blank screen","error message","bug"],"more":[],"a":"Close the app fully and reopen it. Your vault is saved to disk after every change, so you will not lose entries. If it keeps happening, use the message button and tell us what you were doing."},{"id":"contact","q":["contact support","talk to a human","speak to someone","report a problem","feedback","suggest a feature","help me","real person"],"more":[],"a":"I can pass a message to the team. Tap the message button below and write what you need. Do not include passwords, I will only send what you type."}],"pro":[{"id":"what","q":["what is vaultinator","what does this app do","what is this","who made this app","about the app"],"more":[],"a":"Vaultinator Pro is the extended edition of Vaultinator. It keeps your logins, cards, documents and more in one encrypted vault that only your master password opens, on your computer and phone, with nothing in the cloud."},{"id":"create-vault","q":["how do i create a vault","set up my vault","first time setup","make a new vault","get started","i just installed it what now","new account"],"more":[],"a":"On the first screen choose Create Vault, type a master password twice and tap Create Vault. The strength meter shows how tough it is. Pick something long you can remember, like four random words."},{"id":"master-password","q":["what is the master password","which password do i use to unlock","master pass","what should my master password be","good master password"],"more":[],"a":"The master password is the one password you remember. It unlocks everything else. Make it long (a phrase of 4+ random words works well) and never reuse it anywhere."},{"id":"forgot-master","q":["i forgot my master password","forgot password","cant unlock vault","reset master password","lost my password","locked out","can you reset my password","password recovery","cant remember my master password","i dont remember my master password","what if i forget my master password"],"more":["recovery"],"a":"There is no reset. Nobody at Vaultinator can open your vault, not even us. If you set up a recovery phrase (Pro), tap \"Forgot password? Use recovery phrase\" on the unlock screen and enter your 12 words. If you did not, the vault cannot be opened, which is what keeps it safe from everyone else."},{"id":"unlock-wrong","q":["it says wrong password","incorrect password","wont unlock","unlock not working","master password not working","caps lock"],"more":["forgot-master","unlock-photo"],"a":"Check caps lock, then tap SHOW next to the field to see what you are typing. If you are sure it is right, make sure you are on the right vault (each device has its own). If you set a recovery phrase you can use it from Forgot password."},{"id":"lock","q":["how do i lock the vault","lock app","log out","sign out","close the vault"],"more":[],"a":"Tap the lock icon at the top right. The vault also locks by itself after the time you pick in Preferences."},{"id":"autolock","q":["auto lock","vault locks by itself","how long until it locks","change lock time","stop it locking","locks too fast","never lock","make the vault lock quicker","make it lock sooner","lock after less time"],"more":[],"a":"Open Preferences, then Security, then \"Auto-lock vault after\". Choose 1, 5, 15 or 30 minutes, or Never. Shorter is safer."},{"id":"add-entry","q":["how do i add a password","save a new login","add entry","new password","store a password","create entry","add account"],"more":[],"a":"Tap Add Entry at the top right. Fill in a title, username and password (use Generate for a strong one), add the website if you like, then Save Entry."},{"id":"edit-entry","q":["how do i edit a password","change a saved password","update an entry","edit entry","rename an entry","fix a typo in an entry"],"more":[],"a":"Tap the entry to open it, change what you need and tap Save."},{"id":"delete-entry","q":["how do i delete a password","remove an entry","delete entry","get rid of a login","delete several","delete multiple entries","bulk delete"],"more":[],"a":"Open the entry and tap Delete. To remove several at once, tick the boxes on the left of each row, then tap Delete Selected. Deleting cannot be undone, so export a backup first if unsure."},{"id":"copy","q":["how do i copy a password","copy username","copy to clipboard","copy without showing","paste my password"],"more":[],"a":"Each row has copy buttons for the username and password, so you never have to show them. The clipboard is cleared automatically after the time set in Preferences."},{"id":"show-password","q":["show password","reveal password","see my password","view password","what is my saved password"],"more":[],"a":"Open the entry and tap the eye to reveal the password. It hides again when you close it."},{"id":"clipboard-clear","q":["clipboard","clear clipboard","copied password stays","how long does copy last","clipboard timer"],"more":[],"a":"Preferences, Security, \"Clear clipboard after copying\": 30 seconds, 1 minute or 2 minutes. After that the copied password is wiped."},{"id":"favorites","q":["favorites","favourite","star an entry","pin to top","quick access entries","mark as favorite"],"more":[],"a":"Tap the star on an entry, or tick \"Add to favorites\" when creating it. The Favorites list on the left shows only those."},{"id":"search","q":["how do i find an entry","search","cant find my password","look up a login","find a password"],"more":[],"a":"Type in the search box at the top. It filters by title and username as you type."},{"id":"categories","q":["categories","folders","organize my passwords","how do i group entries","add a category","create a folder","sort my logins"],"more":[],"a":"Use Add Category in the left sidebar. Give it a name, icon and color, then choose it on any entry. Click a category to see only its entries."},{"id":"nested-folders","q":["folder inside a folder","subfolder","nested folders","move a folder","put a category inside another"],"more":[],"a":"In Pro, hover a category and tap the move button to put it inside another folder, or back to the top level."},{"id":"delete-category","q":["delete a category","remove a folder","what happens to entries when i delete a category"],"more":[],"a":"Hover the category and tap the delete icon. Your entries are not deleted, they just become uncategorized."},{"id":"notes","q":["secure note","store notes","private notes","where do i put text","save a note"],"more":[],"a":"Every entry has a Notes box that is encrypted like the password. In Pro you can also create a Secure note record type."},{"id":"url","q":["website link","open the website","url field","login page link"],"more":[],"a":"Add the website in the Website URL field. It shows on the entry so you can find the right login page quickly."},{"id":"generator","q":["generate a password","password generator","make a strong password","random password","create a password for me","suggest a password"],"more":[],"a":"Tap Generate when adding an entry, or the wand icon at the top. Choose a length, pick which character types to include, and tap Generate again until you like it. Copy it with one tap."},{"id":"passphrase","q":["passphrase","words password","easy to remember password","memorable password","diceware"],"more":[],"a":"In the generator switch to the words mode. Pick how many words, a separator, and whether to capitalize or add a number. Word-based passwords are long, strong and easier to type on a phone."},{"id":"generator-history","q":["i lost the password i generated","generator history","recently used passwords","previous generated passwords"],"more":[],"a":"The generator keeps a \"Recently used\" list at the bottom, so a password you generated but did not save is still there. Use Clear to wipe the list."},{"id":"lookalike","q":["confusing characters","o and 0","look alike characters","password hard to read"],"more":[],"a":"Turn on \"Avoid look-alike characters\" in the generator. It leaves out O, 0, I, l and 1 so you can read the password aloud or type it by hand."},{"id":"strength","q":["password strength","is my password strong","what do the colors mean","entropy","how strong is it"],"more":[],"a":"The strength meter estimates how hard a password is to guess. Longer beats fancier: 16+ characters or 5 random words is strong. Bits of entropy are shown in the generator."},{"id":"totp","q":["two factor codes","2fa","authenticator","one time code","totp","google authenticator replacement","six digit code","authenticator key","otp"],"more":[],"a":"Paste the setup key (or the otpauth:// link) from the site into \"Authenticator key\" on the entry. The entry then shows a rotating six-digit code you can copy. It can take a couple of seconds to appear."},{"id":"totp-wrong","q":["authenticator code is wrong","code not working","2fa code invalid","totp not accepted","code expired","authenticator code isnt working","my 2fa codes are wrong"],"more":[],"a":"Codes depend on the clock. Make sure the date, time and time zone on this device are set automatically. Also check the setup key was pasted fully with no spaces missing."},{"id":"import","q":["import passwords","move from another password manager","bring my passwords from chrome","import csv","switch from lastpass","import from bitwarden","import from 1password","import from keeper","transfer passwords"],"more":[],"a":"Export a CSV from your old manager or browser, then tap the import icon in Vaultinator and pick the file. The format is detected automatically. Delete the CSV afterwards, since it is not encrypted."},{"id":"export","q":["export passwords","backup my vault","download my passwords","save a copy","export csv","back up"],"more":[],"a":"Tap the export icon and choose CSV (opens in other password managers) or a JSON backup. Exports are readable by anyone, so keep them somewhere safe and delete them when done."},{"id":"import-failed","q":["import failed","import not working","import says error","some passwords did not import","import missing entries"],"more":[],"a":"Make sure the file ends in .csv or .json and came straight from the other app without being edited in a spreadsheet that changed the columns. If it still fails, send us the name of the app it came from with the message button."},{"id":"sync","q":["sync with my phone","sync devices","connect phone to computer","use on two devices","transfer to my phone","sync with ios","sync with android","start sync","how does sync work","how do i sync","get sync working"],"more":["sync-subnet","sync-fails"],"a":"There are a few ways to get sync working. They all start on the computer: Preferences, Sync, Start Sync.\n1) Generate QR (easiest): tap Generate QR on the computer, then scan it from the phone app.\n2) Manual entry: if the QR will not scan, type the connection string shown under it into the phone app.\n3) Automatic: with both devices on the same Wi-Fi and matching network settings (same subnet), they should find each other on their own.\nSync goes straight between your own devices with no cloud, and it is in beta. Want more info, like how to check your subnet?"},{"id":"sync-subnet","q":["check subnet","what is my subnet","same network check","how to check network settings","find my ip address","subnet mask","same wifi check","are we on the same network"],"more":["sync-fails"],"a":"Both devices need to be on the same network and subnet. Windows: open Command Prompt, run ipconfig, and read IPv4 Address and Subnet Mask. iPhone: Settings, Wi-Fi, tap the (i) next to your network and read IP Address and Subnet Mask. Android: Settings, Wi-Fi, tap your network, then Advanced or View more for the IP address. Mac: System Settings, Wi-Fi, Details, TCP/IP. The first three numbers of the IP address (like 192.168.1) should match on both devices. Guest networks and VPNs often break this."},{"id":"sync-fails","q":["sync not working","phone wont connect","qr code not scanning","sync failed","cant connect to desktop","sync stuck","devices not syncing"],"more":[],"a":"Check both devices are on the same Wi-Fi (not guest or mobile data), that the computer app is open and unlocked, and that Start Sync is on. If the QR will not scan, type the connection string shown under it. A firewall prompt on the computer must be allowed."},{"id":"cloud","q":["is it in the cloud","cloud backup","online account","do you store my data","where is my data stored","server","sync across the internet","access from anywhere"],"more":[],"a":"No cloud. Your vault is an encrypted file on each of your devices. We have no server holding it. Device sync happens directly between your devices on the same network."},{"id":"new-phone","q":["new phone","i got a new device","move to a new phone","lost my phone","replace device","transfer vault"],"more":[],"a":"On the old device export a backup (or sync to the new one while both are on the same Wi-Fi). On the new device create or open a vault and import the backup. If the old device is gone and you never backed up or synced, the vault cannot be recovered."},{"id":"security","q":["is it safe","how secure is this","encryption","who can see my passwords","is it encrypted","can you see my passwords","zero knowledge","privacy"],"more":[],"a":"Everything is encrypted on your device with a key made from your master password. We never see your passwords, we cannot reset them, and the app makes no accounts. The only network call is the optional breach check, which sends just a partial hash."},{"id":"breach","q":["has my password been leaked","breach check","pwned","have i been pwned","data breach","compromised passwords"],"more":["audit"],"a":"Pro security audit has a Breach check. It tests each password against the Have I Been Pwned list by sending only the first 5 characters of a one-way hash, never the password. It needs internet."},{"id":"audit","q":["security audit","weak passwords","reused passwords","old passwords","check my vault health","which passwords are bad","security score"],"more":[],"a":"Pro security audit scores your vault and lists weak, reused and old passwords and logins missing a two-factor code. Open Preferences and tap Run security audit."},{"id":"unlock-photo","q":["unlock photo","photo of intruder","camera after wrong password","who tried to unlock","wrong password picture"],"more":[],"a":"In Preferences turn on Unlock photo. After a wrong password the front camera takes a picture stamped with date, time and location. View unlock photos shows them, and you can delete any."},{"id":"screenshot","q":["can others see my screen","screenshots","screen recording protection"],"more":[],"a":"Passwords stay hidden until you reveal them and hide again afterwards. Be careful revealing them while screen sharing."},{"id":"hacked","q":["i think i was hacked","someone has my passwords","device stolen","phone was stolen","laptop stolen","what do i do if my device is lost","someone stole my laptop","someone stole my phone","my phone got stolen"],"more":[],"a":"Your vault is encrypted and locked, so a thief needs your master password. Still, change the passwords for your most important accounts (email, bank) from another device, and if you sync to other devices, treat the lost one as compromised until you have changed them."},{"id":"pro-what","q":["what is pro","pro features","pro vs standard","difference between pro and regular","what do i get with pro","upgrade","how much is pro","what does pro include","price","is pro free"],"more":[],"a":"Pro adds 17 record types (cards, bank, passports, Wi-Fi and more), custom fields, encrypted file attachments, change history, nested folders, a recovery phrase, offline sharing, expiry reminders and the security audit with breach check. While in beta, Pro is free to try. Pricing is not announced yet."},{"id":"pro-turn-on","q":["how do i turn on pro","enable pro","activate pro","unlock pro features","where is the pro switch","pro is locked"],"more":[],"a":"During the beta, open Preferences, then Vaultinator Pro, and switch on Pro features. Everything Pro appears right away."},{"id":"record-types","q":["credit card","store a card","payment card","bank account","passport","drivers license","wifi password","ssh key","record types","identity","server login","software license","what can i store"],"more":[],"a":"Pro has 17 record types: Login, Secure note, Payment card, Bank account, Identity, Address, Passport, Driver license, Birth certificate, Health insurance, Wi-Fi network, Server, Database, SSH key, Software license, Membership and Contact. Pick one at the top when adding an entry."},{"id":"custom-fields","q":["custom field","add my own field","security question","extra field","pin field","secret field"],"more":[],"a":"In a Pro entry choose \"Add a custom field\". Types are Text, Secret (hidden), Long text, Date, PIN, Email, Phone and Link. Good for security answers and account numbers."},{"id":"attachments","q":["attach a file","attachments","store a pdf","upload a document","file size limit","save a photo of my passport","add files"],"more":[],"a":"Pro entries can hold encrypted files, up to 15 MB each. Open the entry and use Attach a file, Add photo, or Record voice note. Photos open with View, audio plays with Play, and PDF, Word and Markdown files open with Read, all inside the entry. Save exports any file again."},{"id":"voice-notes","q":["voice note","record audio","audio note","record a voice memo","store audio","play audio","photo preview","view a photo","store pictures","add a picture","save an image","open a pdf","read a word document","view a docx","markdown file","read a pdf","document viewer"],"more":[],"a":"In a Pro entry, tap Record voice note, speak, then Stop and save. It is encrypted and attached to that entry, and Play replays it. For pictures, tap Add photo, then View to see it inside the entry. Folders keep it all organized, because each file lives with its record."},{"id":"history","q":["old password","password history","previous versions","undo a change","i overwrote my password","see earlier values"],"more":[],"a":"Pro keeps earlier values. Open the entry and tap \"Show history\" to see and copy previous passwords, in case a site change went wrong."},{"id":"recovery","q":["recovery phrase","recovery words","twelve words","12 words","backup phrase","set up recovery","emergency sheet"],"more":[],"a":"Pro tools, then Recovery phrase. Enter your master password and create it. You get 12 words and a printable emergency sheet. Anyone holding those words can open the vault on this device, so store the sheet like a passport, away from the computer."},{"id":"share","q":["share a password","send a login to someone","share with family","share file","send entries to another person","give access to my wife"],"more":[],"a":"Pro tools, then Share. Pick entries, set a passphrase and an expiry (never, 24 hours or 7 days) and send the file. Tell them the passphrase by a different route, like a call. They use Open a share file in their Vaultinator Pro. No server involved."},{"id":"expiry","q":["expiry date","expiring","remind me when my passport expires","renewal reminder","license expires","card expiry"],"more":[],"a":"On a Pro record set an Expires date. Anything expiring within 30 days shows in the banner at the top and in Pro tools, Expiring."},{"id":"themes","q":["change theme","dark mode","light mode","colors","appearance","change the look","terminal theme"],"more":[],"a":"Preferences, Appearance, Theme. Choose Brass, Layer, Terminal or Midnight."},{"id":"sound","q":["sound","lock sound","turn off sound","turn on sound","splash sound","noise when opening"],"more":[],"a":"The lock sound on the splash screen is off by default. Turn it on in Preferences, Sound."},{"id":"smith","q":["who is smith","what is smith","who are you","what are you","are you ai","are you a robot","are you real","are you chatgpt"],"more":[],"a":"I am Smith, the lock with opinions. I am a built-in guide, not a smart AI. I know every button in this app, I can point at them, and if I do not know the answer I will pass your question to the professionals."},{"id":"version","q":["what version","app version","beta","is this finished","known issues"],"more":[],"a":"This is Vaultinator Pro 1.0.0 beta. It works, but expect rough edges, especially device sync and the Pro extras. Please report anything odd with the message button."},{"id":"autofill","q":["autofill","browser extension","fill passwords in chrome","auto login","fill in apps","passkeys","face id","fingerprint","biometric"],"more":[],"a":"Not yet. Today you copy the username and password from Vaultinator and paste them in. Browser extension, phone autofill, biometric unlock and passkeys are not built yet. Tell the team if you want them sooner."},{"id":"languages","q":["other languages","spanish","translate the app","change language"],"more":[],"a":"The app is English only for now. Other languages are planned."},{"id":"delete-vault","q":["delete my vault","start over","erase everything","uninstall","remove the app"],"more":[],"a":"Uninstalling removes the app, but the encrypted vault file may stay on the device. Export a backup first if you might need your data. We cannot delete your data remotely because we never have it."},{"id":"two-vaults","q":["multiple vaults","second vault","separate vault for work","two vaults","family vault"],"more":[],"a":"One vault per device for now. Use categories to keep work and personal apart, or use Pro sharing to hand specific entries to another person."},{"id":"app-crash","q":["app crashed","app is frozen","white screen","not responding","app wont open","blank screen","error message","bug"],"more":[],"a":"Close the app fully and reopen it. Your vault is saved to disk after every change, so you will not lose entries. If it keeps happening, use the message button and tell us what you were doing."},{"id":"contact","q":["contact support","talk to a human","speak to someone","report a problem","feedback","suggest a feature","help me","real person"],"more":[],"a":"I can pass a message to the team. Tap the message button below and write what you need. Do not include passwords, I will only send what you type."}],"syn":{"passwd":"password","pass":"password","pw":"password","pwd":"password","passwords":"password","logins":"login","accounts":"account","delete":"remove","erase":"remove","del":"remove","trash":"remove","modify":"edit","change":"edit","update":"edit","fix":"edit","backup":"export","save":"store","phone":"device","mobile":"device","iphone":"device","ios":"device","android":"device","tablet":"device","pc":"computer","laptop":"computer","desktop":"computer","two-factor":"twofactor","mfa":"twofactor","2fa":"twofactor","otp":"twofactor","authenticator":"twofactor","totp":"twofactor","codes":"code","folder":"category","folders":"category","categories":"category","unlock":"unlock","open":"unlock","lock":"lock","locked":"lock","forgot":"forget","forgotten":"forget","lost":"forget","cant":"cannot","wont":"cannot","doesnt":"cannot","can't":"cannot","won't":"cannot","doesn't":"cannot","broken":"cannot","fails":"cannot","failed":"cannot","favourite":"favorite","favourites":"favorite","favorites":"favorite","star":"favorite","hack":"hacked","stolen":"hacked","stole":"hacked","steal":"hacked","isnt":"cannot","arent":"cannot","not":"cannot","leaked":"breach","pwned":"breach","compromised":"breach","safe":"secure","safety":"secure","security":"secure","encrypted":"secure","cost":"price","pay":"price","buy":"price","paid":"price","upgrade":"price","cheap":"price"},"stop":["a","an","the","i","my","me","to","do","how","can","is","it","of","in","on","and","or","for","with","what","why","where","when","does","did","am","are","be","this","that","you","your","we","us","just","please","im","its","if","so","as","at","by","from"]}
"""#
}

private struct SmithMessage: Identifiable {
    enum Who { case smith, you }
    let id = UUID()
    let who: Who
    let text: String
    var alternatives: [SmithEntry] = []
    var followUps: [SmithEntry] = []
    var offerTeam = false
    var asked = ""
}

struct SmithHelpView: View {
    @State private var shown: SmithMessage? = nil
    @State private var asked = ""
    @State private var input = ""
    @State private var teamAsked: String? = nil
    @State private var teamText = ""
    @State private var teamContact = ""
    @State private var sent = false
    @FocusState private var focused: Bool

    var body: some View {
        VStack(spacing: 0) {
            ScrollViewReader { proxy in
                ScrollView {
                    VStack(alignment: .leading, spacing: 12) {
                        Color.clear.frame(height: 0).id("top")
                        if !asked.isEmpty {
                            Text(asked).font(.footnote).foregroundColor(Palette.textSecondary)
                                .frame(maxWidth: .infinity, alignment: .trailing)
                        }
                        if let m = shown { bubble(m) }
                        if teamAsked != nil { teamBox }
                    }
                    .padding(16)
                }
                .onChange(of: shown?.id) { _ in withAnimation { proxy.scrollTo("top", anchor: .top) } }
            }
            Divider().background(Palette.stroke)
            HStack(spacing: 8) {
                TextField("Ask Smith anything", text: $input)
                    .focused($focused)
                    .submitLabel(.send)
                    .onSubmit { send() }
                    .padding(10)
                    .background(RoundedRectangle(cornerRadius: Palette.r(10), style: .continuous).fill(Palette.surfaceRaised))
                Button { send() } label: { Image(systemName: "arrow.up.circle.fill").font(.title2) }
                    .disabled(input.trimmingCharacters(in: .whitespaces).isEmpty)
                    .accessibilityLabel("Send")
            }
            .padding(12)
        }
        .screenBackground()
        .navigationTitle("Ask Smith")
        .navigationBarTitleDisplayMode(.inline)
        .tint(Palette.accent)
        .onAppear {
            if shown == nil {
                shown = (SmithMessage(who: .smith,
                    text: "Hi! I'm Smith, the lock with opinions. I know every button in this app. Ask me anything, or tap a question below.",
                    alternatives: SmithEngine.entries.filter { ["create-vault", "add-entry", "sync", "forgot-master", "security"].contains($0.id) }))
            }
        }
    }

    private func bubble(_ m: SmithMessage) -> some View {
        VStack(alignment: m.who == .you ? .trailing : .leading, spacing: 8) {
            Text(m.text)
                .foregroundColor(m.who == .you ? Palette.onAccent : Palette.textPrimary)
                .padding(12)
                .background(RoundedRectangle(cornerRadius: Palette.r(14), style: .continuous).fill(m.who == .you ? Palette.accent : Palette.surface))
                .frame(maxWidth: .infinity, alignment: m.who == .you ? .trailing : .leading)
            var seen = Set<String>()
            let chips = (m.followUps + m.alternatives).filter { seen.insert($0.id).inserted }
            if !chips.isEmpty {
                VStack(alignment: .leading, spacing: 6) {
                    ForEach(chips) { e in
                        Button { ask(e.q[0]) } label: {
                            Text(e.q[0]).font(.footnote).padding(.horizontal, 10).padding(.vertical, 6)
                                .background(Capsule().fill(Palette.surfaceRaised))
                        }
                    }
                }
            }
            if m.offerTeam {
                Button("Message the team") { teamAsked = m.asked; sent = false }
                    .font(.footnote.weight(.semibold))
            }
        }
    }

    private var teamBox: some View {
        VStack(alignment: .leading, spacing: 8) {
            if sent {
                Text("Saved on this phone. Messages to the team are delivered once team messaging is switched on for this beta.")
                    .font(.footnote).foregroundColor(Palette.textSecondary)
            } else {
                TextField("Tell us what you need. Do not include passwords.", text: $teamText, axis: .vertical)
                    .lineLimit(3...6)
                    .padding(10)
                    .background(RoundedRectangle(cornerRadius: Palette.r(10), style: .continuous).fill(Palette.surfaceRaised))
                TextField("Email or phone so we can reply (optional)", text: $teamContact)
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled()
                    .padding(10)
                    .background(RoundedRectangle(cornerRadius: Palette.r(10), style: .continuous).fill(Palette.surfaceRaised))
                HStack {
                    Button("Cancel") { teamAsked = nil; teamText = "" }
                    Spacer()
                    Button("Send to the team") { queueTeamMessage() }
                        .disabled(teamText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                }
                Text("Only what you type here is sent, plus the app edition and version. Nothing from your vault.")
                    .font(.caption).foregroundColor(Palette.textTertiary)
            }
        }
        .padding(12)
        .background(RoundedRectangle(cornerRadius: Palette.r(14), style: .continuous).fill(Palette.surface))
    }

    private func send() {
        let text = input.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else { return }
        input = ""
        ask(text)
    }

    private func ask(_ question: String) {
        asked = question
        teamAsked = nil
        let result = SmithEngine.answer(question)
        if let hit = result.match {
            let follow = SmithEngine.visible(hit.more.compactMap { id in SmithEngine.entries.first { $0.id == id } }, askedAbout: hit)
            shown = SmithMessage(who: .smith, text: hit.a, alternatives: result.alternatives, followUps: follow)
        } else {
            shown = SmithMessage(who: .smith,
                text: "I am not sure about that one. Try rewording it, pick a suggestion, or I can pass it to the team.",
                alternatives: result.alternatives, offerTeam: true, asked: question)
        }
    }

    private func queueTeamMessage() {
        let defaults = UserDefaults.standard
        var outbox = defaults.array(forKey: "smith_outbox") as? [[String: String]] ?? []
        let info = Bundle.main.infoDictionary
        outbox.append([
            "message": teamText,
            "contact": teamContact,
            "asked": teamAsked ?? "",
            "edition": SmithConfig.edition,
            "version": info?["CFBundleShortVersionString"] as? String ?? "1.0",
            "time": ISO8601DateFormatter().string(from: Date())
        ])
        defaults.set(outbox, forKey: "smith_outbox")
        teamText = ""
        sent = true
    }
}
