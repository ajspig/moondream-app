from dotenv import load_dotenv
import os

from livekit import agents
from livekit.agents import AgentSession, Agent, RoomInputOptions
from livekit.plugins import (
    openai,
    cartesia,
    deepgram,
    noise_cancellation,
    silero,
)
from livekit.plugins.turn_detector.multilingual import MultilingualModel
from livekit.agents import function_tool, Agent, RunContext, ChatContext, ChatMessage
import asyncio
from livekit import rtc
from livekit.agents import Agent, get_job_context
from livekit.agents.llm import ImageContent
from livekit.agents import function_tool, Agent, RunContext
import moondream as md
from PIL import Image
import asyncio

load_dotenv()


class Assistant(Agent):
    def __init__(self) -> None:
        self._latest_frame = None
        self._video_stream = None
        self._tasks = []
        super().__init__(
            instructions="" \
            "You are a helpful voice AI assistant who is helping an visual impaired user navigate the NYC subway system. " \
            "Your goal is to help them successfully navigate the subway system and find their train."
            "You will be provided with a live latest image of the user's surroundings, and you can use this to help them navigate." \
            "You have the following responsibilities:" \
            "1. Greet the user and offer your assistance." \
            "2. Take the user to the platform where they can catch their train." \
            "3. Use crowd detection to help the user navigate through crowded areas and stand at the least crowded part of the platform." \
        )

    async def on_enter(self):
        room = get_job_context().room

        # Find the first video track (if any) from the remote participant
        remote_participant = list(room.remote_participants.values())[0]
        video_tracks = [
            publication.track
            for publication in list(remote_participant.track_publications.values())
            if publication.track.kind == rtc.TrackKind.KIND_VIDEO
        ]
        if video_tracks:
            self._create_video_stream(video_tracks[0])

        # Watch for new video tracks not yet published
        @room.on("track_subscribed")
        def on_track_subscribed(
            track: rtc.Track,
            publication: rtc.RemoteTrackPublication,
            participant: rtc.RemoteParticipant,
        ):
            if track.kind == rtc.TrackKind.KIND_VIDEO:
                self._create_video_stream(track)

    async def on_user_turn_completed(
        self, turn_ctx: ChatContext, new_message: ChatMessage
    ) -> None:
        # Add the latest video frame, if any, to the new message
        if self._latest_frame:
            new_message.content.append(ImageContent(image=self._latest_frame))
            self._latest_frame = None

    # Helper method to buffer the latest video frame from the user's track
    def _create_video_stream(self, track: rtc.Track):
        # Close any existing stream (we only want one at a time)
        if self._video_stream is not None:
            self._video_stream.close()

        # Create a new stream to receive frames
        self._video_stream = rtc.VideoStream(track)

        async def read_stream():
            async for event in self._video_stream:
                # Store the latest frame for use later
                self._latest_frame = event.frame

        # Store the async task
        task = asyncio.create_task(read_stream())
        task.add_done_callback(lambda t: self._tasks.remove(t))
        self._tasks.append(task)

    @function_tool
    async def view_latest_image(
        context: RunContext,
    ) -> dict:
        """Get a description of what the user is seeing"""
        await context.session.say("I'm analyzing the image you shared. This may take a moment...")
        model = md.vl(api_key=os.getenv("MOONDREAM_API_KEY"))
        image = Image.open("../images/port_authority.jpg")
        result = model.query(image, "What's in this image?")
        return { 
            "image_description": result["answer"],
        }
    
    @function_tool
    async def crowd_detection(
        context: RunContext,
    ) -> dict:
        """How many crowds are in the image"""
        await context.session.say("I'm analyzing the image you shared. This may take a moment...")
        model = md.vl(api_key=os.getenv("MOONDREAM_API_KEY"))
        image = Image.open("../images/port_authority.jpg")
        result = model.query(image, "Where are the crowds in this image? Where is the least crowded area?")
        return { 
            "image_description": result["answer"],
        }

async def entrypoint(ctx: agents.JobContext):
    session = AgentSession(
        stt=deepgram.STT(model="nova-3", language="multi"),
        llm=openai.LLM(model="gpt-4o-mini"),
        tts=cartesia.TTS(model="sonic-2", voice="f786b574-daa5-4673-aa0c-cbe3e8534c02"),
        vad=silero.VAD.load(),
        turn_detection=MultilingualModel(),
    )

    await session.start(
        room=ctx.room,
        agent=Assistant(),
        room_input_options=RoomInputOptions(
            # LiveKit Cloud enhanced noise cancellation
            # - If self-hosting, omit this parameter
            # - For telephony applications, use `BVCTelephony` for best results
            noise_cancellation=noise_cancellation.BVC(),
        ),
    )

    await ctx.connect()

    await session.generate_reply(
        instructions="READ IMAGE then Greet the user and offer your assistance."
    )


if __name__ == "__main__":
    agents.cli.run_app(agents.WorkerOptions(entrypoint_fnc=entrypoint))
