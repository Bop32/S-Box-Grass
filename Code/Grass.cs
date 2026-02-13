
using System;
using System.Runtime.InteropServices;
using System.Transactions;


public struct GrassSettings
{
	public Model HighLodGrassModel { get; set; }
	public Model LowLodGrassModel { get; set; }
	public Terrain Terrain { get; set; }
	public int WorldChunksPerRow { get; set; }
	public int SubChunksPerRow { get; set; }
	public int MaxNumberOfUsableChunks { get; set; }
	public int GrassCountPerChunk { get; set; }
	public Vector2 ChunkSize { get; set; }
	public float ClumpStrength { get; set; }
	public float ClumpSize { get; set; }
}

public sealed class Grass : Component
{

	[Property]
	public readonly Model HighLodGrassModel = null;

	[Property]
	public readonly Model LowLodGrassModel = null;

	[Property]
	public readonly Terrain Terrain = null;

	[Header( "World Chunks" )]

	[Property]
	public int WorldChunksPerRow { get; set; }

	[Property]
	public int SubChunksPerRow { get; set; }

	[Property]
	public int MaxNumberOfUsableChunks { get; set; } = 4;

	[Property]
	public int GrassCountPerChunk { get; set; }

	[Property]
	public float ClumpStrength { get; set; } = 5.0f;

	[Property]
	public float ClumpSize { get; set; } = 5.0f;

	GrassCustomObject grass;

	protected override void OnAwake()
	{
		grass = new GrassCustomObject( Scene.SceneWorld, this, GameObject.GetComponent<CameraComponent>() );

		//SimulateChunks();
	}

	public GrassSettings GetSettings()
	{
		return new GrassSettings
		{
			HighLodGrassModel = HighLodGrassModel,
			LowLodGrassModel = LowLodGrassModel,
			Terrain = Terrain,

			GrassCountPerChunk = GrassCountPerChunk,
			SubChunksPerRow = SubChunksPerRow,
			WorldChunksPerRow = WorldChunksPerRow,
			MaxNumberOfUsableChunks = MaxNumberOfUsableChunks,

			ClumpStrength = ClumpStrength,
			ClumpSize = ClumpSize
		};
	}

	private void SimulateChunks()
	{
		int grassPerChunk = GrassCountPerChunk / WorldChunksPerRow;  // 100 / 8 => 12

		Log.Info( SubChunksPerRow );

		int grassPerSubChunk = (grassPerChunk / SubChunksPerRow) + 1;   // 12 / 2 => 6

		for ( int i = 0; i < GrassCountPerChunk; i++ )
		{
			int currentChunk = i / grassPerChunk;
			int localIndexInChunk = i % grassPerChunk;

			int currentSubChunk = localIndexInChunk / grassPerSubChunk;

			Log.Info( $"Grass: `{i}` is in chunk: {currentChunk} and is in subchunk: `{currentSubChunk}`" );

		}
	}

	protected override void DrawGizmos()
	{
		RenderChunks();
	}

	private void RenderChunks()
	{
		float terrainSize = Terrain.TerrainSize;
		float terrainHeight = Terrain.TerrainHeight;

		Vector2 chunkSize = new Vector2( terrainSize / WorldChunksPerRow );

		Vector3 terrainWorldPosition = Terrain.WorldPosition;

		for ( int i = 0; i < WorldChunksPerRow * WorldChunksPerRow; i++ )
		{
			int offsetX = i % WorldChunksPerRow;
			int offsetY = i / WorldChunksPerRow;

			float x = terrainWorldPosition.x + (offsetX + 0.5f) * chunkSize.x;
			float y = terrainWorldPosition.y + (offsetY + 0.5f) * chunkSize.y;
			float z = terrainWorldPosition.z + terrainHeight;

			Vector3 chunkPosition = new Vector3( x, y, z );
			DebugOverlay.Box( chunkPosition, new Vector3( chunkSize, terrainHeight * 2 ), Color.White );
			//RenderSubChunks( chunkPosition, chunkSize, terrainHeight );
		}
	}

	private void RenderSubChunks( Vector3 chunkPosition, Vector2 chunkSize, float terrainHeight )
	{
		Vector2 subChunkSize = new Vector2( chunkSize / SubChunksPerRow );

		Vector3 startSubChunkPosition = new Vector3( chunkPosition.x - chunkSize.x / 2, chunkPosition.y - chunkSize.y / 2, chunkPosition.z );

		for ( int i = 0; i < SubChunksPerRow * SubChunksPerRow; i++ )
		{
			int offsetX = i % SubChunksPerRow;
			int offsetY = i / SubChunksPerRow;

			float x = startSubChunkPosition.x + (offsetX + 0.5f) * subChunkSize.x;
			float y = startSubChunkPosition.y + (offsetY + 0.5f) * subChunkSize.y;
			float z = startSubChunkPosition.z;

			Vector3 subChunkPosition = new Vector3( x, y, z );
			DebugOverlay.Box( subChunkPosition, new Vector3( subChunkSize - 5, terrainHeight * 2 ), Color.Cyan );
		}
	}

	protected override void OnDestroy()
	{
		grass?.DestroyBuffers();
	}

	protected override void OnDisabled()
	{
		grass?.DestroyBuffers();
	}
}
