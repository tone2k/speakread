import Foundation

/// A short public-domain sample so the Read page has something on first launch.
/// Lewis Carroll, Alice's Adventures in Wonderland (1865), the opening of Chapter I.
enum SampleBook {
    static let seededKey = "sampleBookSeeded"
    static let dialogueSeededKey = "sampleDialogueSeeded"

    /// A public-domain dialogue so the cast feature can be heard at once.
    /// Plato, Euthyphro, in Benjamin Jowett's translation: the opening.
    static func makeDialogue() -> Document {
        let document = Document(kind: .book, title: "Euthyphro", author: "Plato · Jowett translation · sample")
        document.chapters = [Chapter(title: "The Porch of the King Archon", text: euthyphro)]
        return document
    }

    private static let euthyphro = """
    PERSONS OF THE DIALOGUE: Socrates, Euthyphro.

    SCENE: The Porch of the King Archon.

    EUTHYPHRO: Why have you left the Lyceum, Socrates? and what are you doing in the Porch of the King Archon? Surely you cannot be concerned in a suit before the King, like myself?

    SOCRATES: Not in a suit, Euthyphro; impeachment is the word which the Athenians use.

    EUTHYPHRO: What! I suppose that some one has been prosecuting you, for I cannot believe that you are the prosecutor of another.

    SOCRATES: Certainly not.

    EUTHYPHRO: Then some one else has been prosecuting you?

    SOCRATES: Yes.

    EUTHYPHRO: And who is he?

    SOCRATES: A young man who is little known, Euthyphro; and I hardly know him: his name is Meletus, and he is of the deme of Pitthis. Perhaps you may remember his appearance; he has a beak, and long straight hair, and a beard which is ill grown.

    EUTHYPHRO: No, I do not remember him, Socrates. But what is the charge which he brings against you?

    SOCRATES: What is the charge? Well, a very serious charge, which shows a good deal of character in the young man, and for which he is certainly not to be despised. He says he knows how the youth are corrupted and who are their corruptors. I fancy that he must be a wise man, and seeing that I am the reverse of a wise man, he has found me out, and is going to accuse me of corrupting his young friends. And of this our mother the state is to be the judge. Of all our political men he is the only one who seems to me to begin in the right way, with the cultivation of virtue in youth; like a good husbandman, he makes the young shoots his first care, and clears away us who are the destroyers of them. This is only the first step; he will afterwards attend to the elder branches; and if he goes on as he has begun, he will be a very great public benefactor.

    EUTHYPHRO: I hope that he may; but I rather fear, Socrates, that the opposite will turn out to be the truth. My opinion is that in attacking you he is simply aiming a blow at the foundation of the state. But in what way does he say that you corrupt the young?

    SOCRATES: He brings a wonderful accusation against me, which at first hearing excites surprise: he says that I am a poet or maker of gods, and that I invent new gods and deny the existence of old ones; this is the ground of his indictment.

    EUTHYPHRO: I understand, Socrates; he means to attack you about the familiar sign which occasionally, as you say, comes to you. He thinks that you are a neologian, and he is going to have you up before the court for this. He knows that such a charge is readily received by the world, as I myself know too well; for when I speak in the assembly about divine things, and foretell the future to them, they laugh at me and think me a madman. Yet every word that I say is true. But they are jealous of us all; and we must be brave and go at them.

    SOCRATES: Their laughter, friend Euthyphro, is not a matter of much consequence. For a man may be thought wise; but the Athenians, I suspect, do not much trouble themselves about him until he begins to impart his wisdom to others, and then for some reason or other, perhaps, as you say, from jealousy, they are angry.

    EUTHYPHRO: I am never likely to try their temper in this way.

    SOCRATES: I dare say not, for you are reserved in your behaviour, and seldom impart your wisdom. But I have a benevolent habit of pouring out myself to everybody, and would even pay for a listener, and I am afraid that the Athenians may think me too talkative. Now if, as I was saying, they would only laugh at me, as you say that they laugh at you, the time might pass gaily enough in the court; but perhaps they may be in earnest, and then what the end will be you soothsayers only can predict.
    """

    static func make() -> Document {
        let document = Document(kind: .book, title: "Alice's Adventures in Wonderland", author: "Lewis Carroll · sample")
        document.chapters = [
            Chapter(title: "Down the Rabbit-Hole", text: chapterOne),
            Chapter(title: "About this sample", text: about)
        ]
        return document
    }

    private static let chapterOne = """
    Alice was beginning to get very tired of sitting by her sister on the bank, and of having nothing to do: once or twice she had peeped into the book her sister was reading, but it had no pictures or conversations in it, "and what is the use of a book," thought Alice, "without pictures or conversations?"

    So she was considering in her own mind (as well as she could, for the hot day made her feel very sleepy and stupid), whether the pleasure of making a daisy-chain would be worth the trouble of getting up and picking the daisies, when suddenly a White Rabbit with pink eyes ran close by her.

    There was nothing so very remarkable in that; nor did Alice think it so very much out of the way to hear the Rabbit say to itself, "Oh dear! Oh dear! I shall be late!" (when she thought it over afterwards, it occurred to her that she ought to have wondered at this, but at the time it all seemed quite natural); but when the Rabbit actually took a watch out of its waistcoat-pocket, and looked at it, and then hurried on, Alice started to her feet, for it flashed across her mind that she had never before seen a rabbit with either a waistcoat-pocket, or a watch to take out of it, and burning with curiosity, she ran across the field after it, and fortunately was just in time to see it pop down a large rabbit-hole under the hedge.

    In another moment down went Alice after it, never once considering how in the world she was to get out again.

    The rabbit-hole went straight on like a tunnel for some way, and then dipped suddenly down, so suddenly that Alice had not a moment to think about stopping herself before she found herself falling down a very deep well.

    Either the well was very deep, or she fell very slowly, for she had plenty of time as she went down to look about her and to wonder what was going to happen next. First, she tried to look down and make out what she was coming to, but it was too dark to see anything; then she looked at the sides of the well, and noticed that they were filled with cupboards and book-shelves; here and there she saw maps and pictures hung upon pegs. She took down a jar from one of the shelves as she passed; it was labelled "ORANGE MARMALADE", but to her great disappointment it was empty: she did not like to drop the jar for fear of killing somebody underneath, so managed to put it into one of the cupboards as she fell past it.

    "Well!" thought Alice to herself, "after such a fall as this, I shall think nothing of tumbling down stairs! How brave they'll all think me at home! Why, I wouldn't say anything about it, even if I fell off the top of the house!" (Which was very likely true.)

    Down, down, down. Would the fall never come to an end? "I wonder how many miles I've fallen by this time?" she said aloud. "I must be getting somewhere near the centre of the earth. Let me see: that would be four thousand miles down, I think."
    """

    private static let about = """
    This sample is here so you can try Verso before you add a book of your own. Press play and watch the ribbon move under each word. Tap any word to start there. Hold the note button while a sentence is read, say what you think, and let go. Your note is pinned to that sentence.

    Open the phone and the chapter becomes two pages with the fold as the spine. Set the phone down half open and the text rises to the top while the controls drop to the flat half. Tap Nightstand for a dark page with a sleep timer.

    To add your own books, use the plus button and pick an EPUB or a PDF. To add a recording from elsewhere, pick an audio file and Verso writes it down.
    """
}
