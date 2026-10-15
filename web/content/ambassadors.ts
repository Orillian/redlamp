// The ambassador programme's page (app/ambassadors). Its source is the programme's plan in the
// private redlamp-social repository (plans/2026-10-15-ambassadors.md); change both together.

export const ambassadors = {
  places: 10,
  intro: [
    "Redlamp is a free raw photo editor for the Mac, in early development. I'm looking for ten photographers to shape it with me.",
    "Ambassadors pick one feature each quarter that I build next, and their edits are shown, with their name, wherever Redlamp is seen. As Redlamp grows, so does the audience their work reaches.",
  ],
  offer: [
    {
      title: "Pick what I build next",
      body: "Each quarter, ambassadors pick one feature from the ones I've accepted for the roadmap, and it goes next. There's a call with me every month, and you see designs before they're built.",
    },
    {
      title: "Your work, credited",
      body: "Your edits made in Redlamp, shown on Redlamp's Instagram and TikTok, on this site, on the blog and in the press kit, always with your name and a link to you.",
    },
    {
      title: "Posts made for you",
      body: "Send me a raw and its edit, and I send back a before-and-after carousel and reel with your settings, ready to post as your own.",
    },
    {
      title: "Founding ambassador",
      body: "The first ten are listed as founding ambassadors on redlamp.app, for good, and in the app once its credits are built.",
    },
  ],
  asks: [
    "One edit a month made in Redlamp: the raw, its .redlamp file, and permission to show it.",
    "Honest feedback, in the monthly call or the ambassadors' channel on Discord.",
    "Saying you're a Redlamp ambassador when you post about Redlamp.",
  ],
  requirements:
    "You'll need an Apple Silicon Mac with macOS 26. Redlamp is in early development, so things break, and you'll be one of the people who tell me when they do.",
  steps: [
    { title: "Edit a photo in Redlamp", body: "Download it free from redlamp.app, open a raw and edit it. Redlamp saves the edit in a .redlamp file beside the photo." },
    { title: "Apply below", body: "Send that photo and its .redlamp file, up to two more, and links to your work." },
    { title: "A short call", body: "If it's a fit, I'll email you to set up 20 minutes to talk about how you edit." },
    { title: "Welcome", body: "You agree the terms, join the ambassadors' channel, and get your ambassador card to post." },
  ],
  questions: [
    {
      q: "Is it paid?",
      a: "No. Being an ambassador is unpaid, and you get nothing other people can't have: no early builds, and no fixes first. Bugs are fixed by how much they hurt, whoever reports them.",
    },
    {
      q: "Do I need a lot of followers?",
      a: "No. I'm looking at your photography, how you share your edits and how your audience talks to you, not how big it is.",
    },
    {
      q: "Who owns my photos?",
      a: "You do. You give me permission to show the photos you send, with credit, and you can take it back for any photo at any time.",
    },
    {
      q: "Do ambassadors decide the roadmap?",
      a: "No. What goes on the roadmap is still my call, and anyone can suggest something with Send Feedback in the app. Ambassadors pick which of the features I've accepted goes next, once a quarter.",
    },
    {
      q: "How is this different from supporting Redlamp?",
      a: "Supporters fund Redlamp's work. Ambassadors give their time, their edits and their feedback. Supporters have a quarterly ranking of their own, and the two don't take from each other.",
    },
    {
      q: "How long is it for?",
      a: "Six months, and we can both agree to carry on. Either of us can stop at any time.",
    },
  ],
  terms: {
    title: "Redlamp ambassador terms",
    paragraphs: [
      "These are the terms between you and Pedro Gomes, who makes Redlamp.",
      "1. What it is. For six months from when you're accepted, you're a Redlamp ambassador. Either of us can end it at any time, by telling the other. At the end of six months we can both agree to carry on.",
      "2. What you do. You edit in Redlamp, and each month you send one edit: the raw, its .redlamp sidecar, and a line about it. When you post about Redlamp, you say you're a Redlamp ambassador. You tell me honestly what works and what doesn't.",
      "3. What I do. You join the ambassadors' monthly call and channel, and the ambassadors' pick of what's built next each quarter. I may show your edits on Redlamp's accounts, website, blog and press kit, always with your name and a link to you, and I send you a ready-to-post version of each one I show.",
      "4. No payment. Being an ambassador is unpaid, on both sides. You get nothing that other people can't have: no early builds and no fixes first.",
      "5. Your photos stay yours. You keep the copyright in everything you send. You give me a non-exclusive, worldwide, royalty-free permission to show the photos and edits you send me, with credit, to promote Redlamp. You can withdraw it for any photo at any time; I then stop using that photo in anything new, and remove it from Redlamp's website and accounts within 14 days.",
      "6. What you confirm. The photos you send are yours to share, and anyone who can be recognised in them has agreed to appear in them publicly.",
      "7. Previews. In the call and the channel I'll show designs before they're built. Please don't post them.",
      "8. Your details. I keep your application and contact details privately, as the privacy note below says.",
    ],
  },
  privacy: {
    title: "Your application",
    text: "I'll use what you send only to consider your application and to reply. It's stored in a private GitHub repository that only I can see, and passes through Vercel, which hosts this site, on the way. If you're not accepted, I delete your application within six months. If you are, I keep your contact details for as long as you're an ambassador, and delete them within six months after. You can ask me to delete them at any time: reply to my email, or write to the address on the email I send you. Your photos are only shown publicly if you're accepted, as the terms say.",
  },
};
