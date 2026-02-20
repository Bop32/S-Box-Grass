
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

	private Vector2 WorldToTexelCPU( Vector2 worldXY, uint texWidth, uint texHeight )
	{
		Vector2 uv = (worldXY - new Vector2( Terrain.WorldPosition )) / Terrain.TerrainSize;
		int x = (int)(uv.x * (texWidth - 1));
		int y = (int)(uv.y * (texHeight - 1));
		return new Vector2( x, y );
	}

	private float SampleHeightCPU( Vector2 texel )
	{
		int w = Terrain.HeightMap.Width;
		int h = Terrain.HeightMap.Height;

		// Clamp texel coordinates exactly like GPU
		int x = (int)Math.Clamp( texel.x, 0, w - 1 );
		int y = (int)Math.Clamp( texel.y, 0, h - 1 );

		return Terrain.HeightMap.GetPixel( x, y ).r / 255.0f * Terrain.TerrainHeight;
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

			Vector3 min = new Vector3( chunkPosition.x - chunkSize.x * 0.5f, chunkPosition.y - chunkSize.y * 0.5f, terrainWorldPosition.z );
			Vector3 max = new Vector3( chunkPosition.x + chunkSize.x * 0.5f, chunkPosition.y + chunkSize.y * 0.5f, z );

			Color visibleColor = AABBInsideFrustum( min, max, GetCameraFrustum() ) ? Color.Green : Color.White;

			DebugOverlay.Box( new BBox( min, max ), visibleColor );
			RenderSubChunks( chunkPosition, chunkSize , i);
		}
	}

	private void RenderSubChunks( Vector3 chunkPosition, Vector2 chunkSize, int index)
	{
		Vector2 subChunkSize = new Vector2( chunkSize / SubChunksPerRow );

		Vector3 startSubChunkPosition = new Vector3( chunkPosition.x - chunkSize.x / 2, chunkPosition.y - chunkSize.y / 2, chunkPosition.z );

		uint textureWidth = (uint)Terrain.HeightMap.Width;
		uint textureHeight = (uint)Terrain.HeightMap.Height;

		for ( int i = 0; i < SubChunksPerRow; i++ )
		{
			int offsetX = i % SubChunksPerRow;
			int offsetY = i / SubChunksPerRow;

			float x = startSubChunkPosition.x + (offsetX + 0.5f) * subChunkSize.x;
			float y = startSubChunkPosition.y + (offsetY + 0.5f) * subChunkSize.y;
			float z = startSubChunkPosition.z;

			Vector3 subChunkPosition = new Vector3( x, y, z );
			Vector2 half = subChunkSize * 0.5f;
			
			float height = GetHeightValue( subChunkPosition, half );

			Vector3 min = new Vector3( subChunkPosition.x - subChunkSize.x * 0.5f + 1.0f, subChunkPosition.y - subChunkSize.y * 0.5f, Terrain.WorldPosition.z + height);
			Vector3 max = new Vector3( subChunkPosition.x + subChunkSize.x * 0.5f, subChunkPosition.y + subChunkSize.y * 0.5f, Terrain.WorldPosition.z + height + height );

			Vector3 cameraPos = Gizmo.Camera.Position;
			float distance = Vector3.DistanceBetween( min, cameraPos );
			float zOffset = distance * 0.005f;
			float xOffset = distance * 0.005f;
			min.z -= zOffset;
			min.x += xOffset;

			string visible = AABBInsideFrustum( min, max, GetCameraFrustum() ) ? "Visible" : "Not Visible";

			BBox box = new( min, max );
			DebugOverlay.Text( box.Center, visible, 256 );

			DebugOverlay.Box( box, GetChunkColor(offsetX + index, offsetY + index ) );
		}
	}

	private Color GetChunkColor( int offsetX, int offsetY )
	{
		// Simple hash from the chunk indices
		int hash = offsetX * 73856093 ^ offsetY * 19349663; // prime numbers
		hash &= 0xFFFFFF; // keep 24 bits

		// Convert hash to RGB 0-1
		float r = ((hash >> 16) & 0xFF) / 255f;
		float g = ((hash >> 8) & 0xFF) / 255f;
		float b = (hash & 0xFF) / 255f;

		return new Color( r, g, b );
	}

	private float GetHeightValue( Vector3 subChunkPosition, Vector2 half )
	{
		Vector2 bottomLeft = new Vector2( subChunkPosition.x - half.x, subChunkPosition.y - half.y );
		Vector2 bottomRight = new Vector2( subChunkPosition.x + half.x, subChunkPosition.y - half.y );
		Vector2 topLeft = new Vector2( subChunkPosition.x - half.x, subChunkPosition.y + half.y );
		Vector2 topRight = new Vector2( subChunkPosition.x + half.x, subChunkPosition.y + half.y );

		Vector2 bottomLeftTexel = WorldToTexelCPU( bottomLeft, (uint)Terrain.HeightMap.Width, (uint)Terrain.HeightMap.Height );
		Vector2 bottomRightTexel = WorldToTexelCPU( bottomRight, (uint)Terrain.HeightMap.Width, (uint)Terrain.HeightMap.Height );
		Vector2 topLeftTexel = WorldToTexelCPU( topLeft, (uint)Terrain.HeightMap.Width, (uint)Terrain.HeightMap.Height );
		Vector2 topRightTexel = WorldToTexelCPU( topRight, (uint)Terrain.HeightMap.Width, (uint)Terrain.HeightMap.Height );

		float height = MathF.Max(MathF.Max( SampleHeightCPU( bottomLeftTexel ), SampleHeightCPU( bottomRightTexel ) ),
			MathF.Max( SampleHeightCPU( topLeftTexel ), SampleHeightCPU( topRightTexel ) ));
		return height;
	}

	public bool AABBInsideFrustum( Vector3 min, Vector3 max, FrustumPlane[] frustumPlanes )
	{
		for ( int i = 0; i < 6; i++ )
		{
			Vector3 normal = frustumPlanes[i].Normal;

			Vector3 positive = new Vector3( normal.x >= 0 ? max.x : min.x, normal.y >= 0 ? max.y : min.y, normal.z >= 0 ? max.z : min.z );

			if ( Vector3.Dot( normal, positive ) - frustumPlanes[i].Distance < 0 ) return false;
		}

		return true;
	}

	private FrustumPlane[] GetCameraFrustum()
	{
		Frustum frustum = GameObject.GetComponent<CameraComponent>().GetFrustum();

		FrustumPlane[] planes = new FrustumPlane[6];

		const float shrinkAmount = 50.0f;

		planes[0] = new FrustumPlane { Normal = frustum.RightPlane.Normal, Distance = frustum.RightPlane.Distance - shrinkAmount };
		planes[1] = new FrustumPlane { Normal = frustum.LeftPlane.Normal, Distance = frustum.LeftPlane.Distance - shrinkAmount };
		planes[2] = new FrustumPlane { Normal = frustum.TopPlane.Normal, Distance = frustum.TopPlane.Distance - shrinkAmount };
		planes[3] = new FrustumPlane { Normal = frustum.BottomPlane.Normal, Distance = frustum.BottomPlane.Distance - shrinkAmount };
		planes[4] = new FrustumPlane { Normal = frustum.NearPlane.Normal, Distance = frustum.NearPlane.Distance - shrinkAmount };
		planes[5] = new FrustumPlane { Normal = frustum.FarPlane.Normal, Distance = frustum.FarPlane.Distance - shrinkAmount };

		return planes;
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
