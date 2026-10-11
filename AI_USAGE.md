# AI usage

Here at Trace Labs we love transparency. AI usage is a contentious thing in the modern world, so we'd like to be upfront about the fact that we _do_ use AI (the latest Claude Opus model, 5.5 at the time of writing) to help build and maintain this repository. We'd also like to be transparent about _how_ AI is used in this repository. In this way we hope to allow our users to make informed choices in managing any perceived risk from utilizing a repository that is partially maintained by AI.

## What the assistant does

- **Writes targeted code**: packaging files, build and publish scripts, and docs, always for a specific task the team gives it. Claude never gets free rein to generate code.
- **Helps test**: running build and install tests, and checking that changes behave the way they should. This helps catch any issues before they make it out to our users.
- **Helps investigate**: reading logs, tracing dependency problems, and summarising what it finds. It's used as a tool to aid analysis, not a tool to conduct end-to-end diagnosis and error resolution. An actual human is responsible for each bugfix.
- **Generate docs**: AI assisted in generating most of these docs, but a human reviewed and edited all of them. We'll be shifting more to human-written docs as time and resources allow!
- **Spellchecking**: it caught a couple of spelling and gramatical errors in this doc after I finished writing it.

## What stays with the team

- **Review.** A team member reads and reviews every change before it's committed, and the team does its own testing and analysis on top of whatever the assistant ran.
- **Production builds.** Most of this process is automated, but each production build is performed and tested extensively by an actual human before it's released.
- **Signing keys.** The assistant never has access to the signing keys. Every signature on this repository is made by a team member.
- **Tool curation and publishing.** The team makes the final decision about what ships, and every push to <https://apt.tracelabs.org> is done by a team member following extensive testing.

## A note on security

The safeguards that protect users don't depend on any of this. CI never signs or publishes, and both `apt` and `qvm-template` reject anything that isn't signed by the [repository key](README.md#signing-key) and anything that has been tampered with in transit. The security of this repository hinges on the security of Ed25519 signatures and the various hashing algorithms we use in different parts of this project, not on the various scripts in this git repository.

Questions or concerns are welcome as an [issue](https://github.com/tracelabs/tlosint-apt-repository/issues).
