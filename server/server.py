import os
from livekit import api
from fastapi import FastAPI

app = FastAPI()


@app.get("/getToken")
def get_token():
    token = (
        api.AccessToken(os.getenv("LIVEKIT_API_KEY"), os.getenv("LIVEKIT_API_SECRET"))
        .with_identity("identity")
        .with_name("my name")
        .with_grants(
            api.VideoGrants(
                room_join=True,
                room="my-room",
            )
        )
    )
    return {"token": token.to_jwt()}


# Run using  uv run fastapi dev server.py
