document.addEventListener("DOMContentLoaded", function () {
    const fileInput = document.getElementById("photo");
    const button = document.getElementById("upload-btn");
    const help = document.querySelector(".upload-area-label span.sub");

    if (!fileInput || !button || !help) {
        return;
    }

    fileInput.addEventListener("change", function () {
        if (fileInput.files.length > 0) {
            help.textContent = "Selected: " + fileInput.files[0].name;
            button.disabled = false;
            button.style.opacity = "1";
            button.textContent = "INITIALIZE UPLOAD ->";
        }
    });
});
