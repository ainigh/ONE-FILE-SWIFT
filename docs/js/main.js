/* main.js: start the app: everything above is defined by now. */
"use strict";
S = fresh();
loadPlan();
setRole("b");
openFromHash();
render(true);
requestAnimationFrame(loop);
