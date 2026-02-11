
using System;
using System.Transactions;


public struct GrassSettings
{
	public Model HighLodGrassModel { get; set; }
	public Model LowLodGrassModel { get; set; }
	public Terrain Terrain { get; set; }
	public int GrassCountPerChunk { get; set; }
	public int ChunkCount { get; set; }
	public Vector2 ChunkSize { get; set; }
	public float ClumpStrength { get; set; }
	public float ClumpSize { get; set; }
}

public sealed class Grass : Component
{

	[Property]
	private readonly Model highLodGrassModel = null;

	[Property]
	private readonly Model lowLodGrassModel = null;

	[Property]
	private readonly Terrain terrain = null;

	[Property]
	public int grassCountPerChunk = 0;

	[Property]
	public int chunkCount = 0;

	[Property]
	public Vector2 chunkSize = Vector2.Zero;

	[Property]
	private readonly float clumpStrength = 5.0f;

	[Property]
	private readonly float clumpSize = 5.0f;

	GrassCustomObject grass;

	protected override void OnAwake()
	{
		grass = new GrassCustomObject( Scene.SceneWorld, this, GameObject.GetComponent<CameraComponent>() );
	}

	public GrassSettings GetSettings()
	{
		return new GrassSettings
		{
			HighLodGrassModel = highLodGrassModel,
			LowLodGrassModel = lowLodGrassModel,
			Terrain = terrain,

			GrassCountPerChunk = grassCountPerChunk,
			ChunkCount = chunkCount,
			ChunkSize = chunkSize,

			ClumpStrength = clumpStrength,
			ClumpSize = clumpSize
		};
	}

	//protected override void DrawGizmos()
	//{
	//	float terrainSize = terrain.TerrainSize;
	//	float terrainHeight = terrain.TerrainHeight;

	//	int chunksPerRow = 8;
	//	Vector2 chunkSize = new Vector2( terrainSize / chunksPerRow );

	//	Vector3 terrainWorldPosition = terrain.WorldPosition;

	//	for ( int i = 0; i < chunksPerRow * chunksPerRow; i++ )
	//	{
	//		int offsetX = i % chunksPerRow;
	//		int offsetY = i / chunksPerRow;

	//		float x = terrainWorldPosition.x + (offsetX + 0.5f) * chunkSize.x;
	//		float y = terrainWorldPosition.y + (offsetY + 0.5f) * chunkSize.y;
	//		float z = terrainWorldPosition.z + terrainHeight;

	//		Vector3 chunkPosition = new Vector3( x, y, z );
	//		DebugOverlay.Box( chunkPosition, new Vector3( chunkSize, terrainHeight * 2 ), Color.Cyan );
	//	}

	//}

	protected override void OnDestroy()
	{
		grass.DestroyBuffers();
	}

	protected override void OnDisabled()
	{
		grass.DestroyBuffers();
	}
}
