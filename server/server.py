import os
from livekit import api
from fastapi import FastAPI
from dotenv import load_dotenv

# Load environment variables from .env file
load_dotenv()

app = FastAPI()


@app.get("/getToken")
def get_token():
    try:
        # Now these will load from your .env file
        api_key = os.getenv("LIVEKIT_API_KEY")
        api_secret = os.getenv("LIVEKIT_API_SECRET")

        if not api_key or not api_secret:
            raise Exception("Missing LIVEKIT_API_KEY or LIVEKIT_API_SECRET")

        token = (
            api.AccessToken(api_key, api_secret)
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
    except Exception as e:
        print(f"Error: {e}")
        raise


# Run using  uv run fastapi dev server.py
