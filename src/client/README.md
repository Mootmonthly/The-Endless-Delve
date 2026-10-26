# src/client — presentation layer (stub)

Rendering, input, UI, camera, audio and animation for the 2D top-down view.
The client is presentation only: it turns player input into intents for the
server and displays the results the server broadcasts.
It must never roll dice or resolve rules on its own authority; anything it
predicts locally is cosmetic and is overwritten by server state.
Character creator, HUD, combat log and safe-zone UI will live here.
