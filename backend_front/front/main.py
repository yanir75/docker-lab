from flask import *
import socket

app = Flask(__name__)


@app.route("/", methods=["GET", "POST"])
def home():
    if request.method == "POST":
        name = request.form["name"]
        print(f"Writing {name}")
        HOST = "back"  # The server's hostname or IP address
        PORT = 10000  # The port used by the server

        with socket.socket(socket.AF_INET, socket.SOCK_STREAM) as s:
            s.connect((HOST, PORT))
            s.sendall((name+ '\n').encode())
            data = s.recv(1024)

        print(f"Received {data!r}")
        return f'Wrote "{name}" to the file <br> Thanks for using my awesome site'

    return render_template("home.html")

if __name__ == "__main__":
    app.run(host="0.0.0.0",port=10000)

