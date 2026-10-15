// The ambassador programme's page (app/ambassadors). Its source is the programme's plan in the
// private redlamp-social repository (plans/2026-10-15-ambassadors.md); change both together.

export const ambassadors = {
  places: 10,
  contact: "pdcgomes@gmail.com",
  intro: [
    "Redlamp is a free raw photo editor for the Mac, in early development. I'm looking for photographers to be its ten founding ambassadors.",
    "Ambassadors propose features and recommend which should come first. Each quarter, they also pick one feature from my shortlist, and I build it next. I show their edits, with their name, wherever Redlamp is seen. Redlamp is new, and its audience is still small: 283 stars on GitHub on 15 October, and its Instagram and TikTok accounts start posting on 27 October. As it grows, more people see your work.",
  ],
  offer: [
    {
      title: "Help decide what I build next",
      body: "You propose features and recommend what to build next, in a monthly call with me and in the ambassadors' channel, where you also see designs before they're built. Each quarter, the ambassadors pick one feature together from a shortlist of three to five I draw from the roadmap, and I build it next.",
    },
    {
      title: "Your work, credited",
      body: "I show your Redlamp edits on Redlamp's Instagram and TikTok, on this site, on the blog and in the press kit, always with your name and a link to you.",
    },
    {
      title: "Posts made for you",
      body: "Send me a raw and its edit, and I send back a before-and-after carousel and reel with your settings, ready to post as your own.",
    },
    {
      title: "Founding ambassador",
      body: "The first ten are listed as founding ambassadors on redlamp.app, for good.",
    },
  ],
  asks: [
    "One edit a month made in Redlamp: the raw, its .redlamp file, and permission to show it.",
    "Ideas for what to build and honest feedback, in the monthly call or the ambassadors' channel on Discord.",
    "Saying you're a Redlamp ambassador when you post about Redlamp.",
  ],
  requirements:
    "You'll need an Apple Silicon Mac with macOS 26 or later. Redlamp is in early development, so things break, and you'll be one of the people who tell me when they do.",
  steps: [
    { title: "Edit a photo in Redlamp", body: "Download it free from redlamp.app, edit a raw, and export it. The exported photo carries your settings." },
    { title: "Apply below", body: "Send the export, with up to two more photos and links to your work." },
    { title: "A short call", body: "If it's a fit, I'll email you to set up 20 minutes to talk about how you edit." },
    { title: "Welcome", body: "You join the ambassadors' channel on Discord, and I send you your ambassador card to post." },
  ],
  questions: [
    {
      q: "Is it paid?",
      a: "No. Being an ambassador is unpaid, and you get nothing in the app that other people can't have: no early builds, and no fixes first. Bugs are fixed by how much they hurt, whoever reports them.",
    },
    {
      q: "Do I need a lot of followers?",
      a: "No. I look at your photography and how you share your edits, and at how your audience talks to you, not how many follow you.",
    },
    {
      q: "Who owns my photos?",
      a: "You do. You give me permission to show the photos you send, with credit, and you can take it back for any photo at any time.",
    },
    {
      q: "How much say do ambassadors have?",
      a: "You propose features and recommend which should come first, and each quarter the ambassadors pick one feature from a shortlist I draw from the roadmap, which I build next. I make the final call on what goes on the roadmap, so not everything you propose gets built.",
    },
    {
      q: "How is this different from supporting Redlamp?",
      a: "Supporters will fund Redlamp. Ambassadors send their edits and help decide what I build next, in the monthly call and with their quarterly pick. Supporters will rank the roadmap each quarter too, separately. If both pick the same feature, the ambassadors' second choice goes next as well.",
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
      "2. What you do. You edit in Redlamp, and each month you send one edit: the raw, its .redlamp file, and a line about it. When you post about Redlamp, you say you're a Redlamp ambassador. You tell me honestly what works and what doesn't, and what you think I should build next.",
      "3. What I do. I add you to the ambassadors' monthly call and channel. Each quarter, the ambassadors pick one feature from a shortlist I draw from the roadmap, and I build it next. I make the final call on what goes on the roadmap. I may show your edits on Redlamp's accounts, website, blog and press kit, always with your name and a link to you, and I send you a ready-to-post version of each one I show.",
      "4. No payment. Being an ambassador is unpaid: neither of us pays the other. You get nothing in the app that other people can't have: no early builds and no fixes first.",
      "5. Your photos stay yours. You keep the copyright in everything you send. You give me a non-exclusive, worldwide, royalty-free permission to show the photos and edits you send me, with credit, to promote Redlamp. You can withdraw it for any photo at any time; I then stop using that photo in anything new, and remove it from Redlamp's website and accounts within 14 days.",
      "6. What you confirm. The photos you send are yours to share, and anyone who can be recognised in them has agreed to appear in them publicly.",
      "7. Previews. In the call and the channel I'll show designs before they're built. Please don't post them.",
      "8. Your details. I keep your application and contact details privately, as the privacy note below says.",
    ],
  },
  privacy: {
    title: "Your application",
    text: "I'll use what you send only to consider your application and to reply. It's stored in a private GitHub repository that only I have access to, and passes through Vercel, which hosts this site, on the way. I use AI agents in Cursor to help me read and sort applications; I make every decision myself. If you're not accepted, I delete your application within six months. If you are, I keep your contact details for as long as you're an ambassador, and delete them within six months after. You can ask me to delete them at any time, at the address below. Your photos are only shown publicly if you're accepted, as the terms say.",
  },
};
