const express = require("express");
const app = express();

app.get("/", (req, res) => {
    res.send("test server on");
});

app.listen(3000, () => {
    console.log("server on 3000")
})