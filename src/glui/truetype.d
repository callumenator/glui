// Written in the D programming language.

/**
* Copyright: Copyright 2012 -
* License: $(WEB www.boost.org/LICENSE_1_0.txt, Boost License 1.0).
* Authors: Callum Anderson
* Revised: July 24, 2012
* Summary: Functions for loading and rendering truetype fonts using FreeType
* context creation.
*/

module glui.truetype;

import
    std.path,
    std.conv,
    std.stdio,
    std.math;

import
    derelict.freetype.ft,
    derelict.opengl.gl,
    derelict.util.exception;


// Font loader, using FreeType
public
{
    // Structure to store everything associated with a particular font and size
    class Font
    {
        FT_Face m_face;
        float m_ptSize = 0;
        float[] m_wids, m_xoffs;
        GLfloat[] m_vertices; // vertex, texcoord, vertex, texcoord, etc.
        GLushort[] m_indices;

        GLuint m_texture;

        float m_lineHeight = 0; // vertical space required between lines of text
        float m_maxHeight = 0, m_maxWidth = 0, m_maxHoss = 0;
        uint m_vertexBuffer;
        uint m_indexBuffer;
    }

    // Create a font from the given file, with the given size
    Font loadFont(string filename, int pointSize)
    {
        // See if it is already loaded
        auto keyname = baseName(filename) ~ pointSize.to!string;
        auto fontPtr = keyname in m_loadedFonts;
        if (fontPtr !is null)
            return *fontPtr;

        Font font = new Font;
        string fontName = baseName(baseName(filename)) ~ to!string(pointSize);
        FontGlyph glyph = loadFontGlyph(filename, pointSize);

        if (glyph.m_face is null)
        {
            // Glyph was not loaded.
            throw new Exception("Could not load " ~ filename);
            return font;
        }

        font.m_face = glyph.m_face;
        int ret = createFont(glyph, font);

        // Store the loaded font
        m_loadedFonts[keyname] = font;

        return font;
    }

    // Create a set of fonts from a list of files, with the given sizes
    void loadFonts(string[] filenames, int[] pointSizes)
    in
    {
        assert(filenames.length == pointSizes.length);
    }
    body
    {
        foreach(idx, file; filenames)
        {
            loadFont(file, pointSizes[idx]);
        }
    }

    // Get kerning info
    int[2] getKerning(Font font, char left, char right)
    in
    {
        assert(cast(int)left >= 32 && cast(int)left <= 126 &&
               cast(int)right >= 32 && cast(int)right <= 126 );
    }
    body
    {
        FT_Vector delta;
        auto glyph_left = FT_Get_Char_Index( font.m_face, left );
        auto glyph_right = FT_Get_Char_Index( font.m_face, right );
        FT_Get_Kerning(font.m_face, glyph_left, glyph_right, 0, &delta);
        return [cast(int)delta.x, cast(int)delta.y];
    }

    // Call before rendering characters from a given font
    void bindFontBuffers(ref const(Font) font)
    {
        if (font is null)
            return;

        // Bind the vertex buffer
        glBindBuffer(GL_ARRAY_BUFFER, font.m_vertexBuffer);
        // Enable VBO
        glEnableClientState(GL_VERTEX_ARRAY);
        glVertexPointer(2, GL_FLOAT, GLfloat.sizeof*4, cast(void*)0);
        // Enable texture VBO
        glEnableClientState(GL_TEXTURE_COORD_ARRAY);
        glTexCoordPointer(2, GL_FLOAT, GLfloat.sizeof*4, cast(void*)(2*GLfloat.sizeof));
        // Bind the index buffer
        glBindBuffer(GL_ELEMENT_ARRAY_BUFFER, font.m_indexBuffer);
        // Bind the texture atlas
        glBindTexture(GL_TEXTURE_2D, font.m_texture);
        // Set texture environment
        glTexEnvf(GL_TEXTURE_ENV, GL_TEXTURE_ENV_MODE, GL_REPLACE);
    }

    // Call after rendering characters from a given font
    void unbindFontBuffers(ref const(Font) font)
    {
        if (font is null)
            return;

        // Bind the zero buffer, to re-enable non-VBO drawing.
        glBindBuffer(GL_ARRAY_BUFFER, 0);
        glBindBuffer(GL_ELEMENT_ARRAY_BUFFER, 0);
        glBindTexture(GL_TEXTURE_2D, 0);

        // Disable client states.
        glDisableClientState(GL_VERTEX_ARRAY);
        glDisableClientState(GL_TEXTURE_COORD_ARRAY);
    }

    // Render a character
    void renderCharacter(ref const(Font) font, char c, float[4] color, float[4] bgcolor)
    in
    {
        assert (cast(uint)c >= 32 && cast(uint)c <= 126 && font !is null);
    }
    body
    {
        auto index = (cast(uint)c) - 32;

        bindFontBuffers(font);

        glColor4fv(bgcolor.ptr);
        glDrawElements(GL_QUADS, 4, GL_UNSIGNED_SHORT, cast(void*)(4*95*typeof(font.m_indices[0]).sizeof));

        glColor4fv(color.ptr);
        glTranslatef(font.m_xoffs[index], 0, 0);
        glDrawElements(GL_QUADS, 4, GL_UNSIGNED_SHORT, cast(void*)(4*index*typeof(font.m_indices[0]).sizeof));

        unbindFontBuffers(font);
    }

    // Render a string of characters at the current position
    void renderCharacters(ref const(Font) font, string text, float[4] color)
    {
        if (font is null)
            return;

        bindFontBuffers(font);
        glColor4fv(color.ptr);

        float xoffset = 0;
        foreach(char c; text)
        {
            bool norender = false;

            if (c == '\n')
            {
                glTranslatef(-xoffset, -1*font.m_lineHeight, 0);
                xoffset = 0;
                norender = true;
            }

            if (!norender)
            {
                auto index = (cast(uint)c) - 32;

                glTranslatef(font.m_xoffs[index], 0, 0);
                glDrawElements(GL_QUADS, 4, GL_UNSIGNED_SHORT, cast(void*)(4*index*typeof(font.m_indices[0]).sizeof));

                xoffset += font.m_wids[index];
                glTranslatef(font.m_wids[index] - font.m_xoffs[index], 0, 0);
            }
        }

        unbindFontBuffers(font);
    }


    // Render a string of characters at the current position, with a background color
    void renderCharacters(ref const(Font) font, string text, float[4] color, float[4] bgcolor)
    {
        if (font is null)
            return;

        bindFontBuffers(font);

        float xoffset = 0;
        foreach(char c; text)
        {
            bool norender = false;

            if (c == '\n')
            {
                glTranslatef(-xoffset, -1*font.m_lineHeight, 0);
                xoffset = 0;
                norender = true;
            }

            if (!norender)
            {
                auto index = (cast(uint)c) - 32;

                glColor4fv(bgcolor.ptr);
                glDrawElements(GL_QUADS, 4, GL_UNSIGNED_SHORT, cast(void*)(4*95*typeof(font.m_indices[0]).sizeof));

                glColor4fv(color.ptr);
                glTranslatef(font.m_xoffs[index], 0, 0);
                glDrawElements(GL_QUADS, 4, GL_UNSIGNED_SHORT, cast(void*)(4*index*typeof(font.m_indices[0]).sizeof));

                xoffset += font.m_wids[index];
                glTranslatef(font.m_wids[index] - font.m_xoffs[index], 0, 0);
            }
        }

        unbindFontBuffers(font);
    }


    // get the horizontal length in screen coords of the line of text
    float getLineLength(string text, Font font)
    {
        if (font is null)
            return 0.0;

        float length = 0;
        foreach(char c; text)
        {
            int idx = (cast(int)c) - 32;
            if (idx >= 0)
                length += font.m_wids[idx];
        }
        return length;
    }


} // public functions




private
{

    // Static AA for remembering loaded fonts and retrieving by name
    Font[string] m_loadedFonts;

    // Handle for a font glyph
    struct FontGlyph
    {
        float   m_ptSize = 0;
        FT_Face m_face = null;
    }

    static FT_Library m_fontLib = null; // Handle to FreeType.

    // Handle missing symbols from Freetype library
    static bool FTMissingSymbols(string libName, string procName)
    {
        writefln("Unable to load: %s, in %s", procName, libName);
        return true;
    }

    // Load the FreeType library, and initialise
    static this()
    {
        if (m_fontLib is null)
        {
            Derelict_SetMissingProcCallback(&FTMissingSymbols);
            DerelictFT.load();
            int err = FT_Init_FreeType(&m_fontLib);
        }
    }

	// Load a TTF font file
    FontGlyph loadFontGlyph(string filename, int ptSize)
	{
        FontGlyph newFont;
        if (FT_New_Face(m_fontLib, (filename~"\0").ptr, 0, &newFont.m_face))
        {
            // Could not load.
            throw new Exception("Could not load font face!");
        }

	    FT_Set_Char_Size(newFont.m_face, ptSize * 64, ptSize * 64, 96, 96);
	    newFont.m_ptSize = ptSize;
        return newFont;
    }

    // For a given font, create the texture for a given character
    int createFontTextures(FontGlyph fg, ref Font font, int maxWidth, int maxHeight)
    {
        FT_Face face = fg.m_face;

        int fullWidth = 96*maxWidth; // an extra one for drawing the background (95 + 1)
        int fullHeight = maxHeight;
        uint fullSize = 2*fullWidth*fullHeight;
        GLubyte[] fullData;
        fullData.length = fullSize;

        uint i, j;
        for (uint index = 32; index < 128; ++index)  // we do an extra one at the end for a blank bitmap
	    {
	        uint aindex = index - 32;
	        int width = 0, height = 0;
            uint offset = 2*(index - 32) * (maxWidth);

            float txlo = 0, txhi = 0, tylo = 0, tyhi = 0;
            float vxlo = 0, vxhi = 0, vylo = 0, vyhi = 0;

            if (index < 127)
            {
                if (FT_Load_Glyph(face, FT_Get_Char_Index(face,cast(char)index), FT_LOAD_DEFAULT))
                return -1;

                FT_Render_Glyph(face.glyph, FT_Render_Mode.FT_RENDER_MODE_NORMAL);
                FT_Bitmap bitmap = face.glyph.bitmap;

                width = nextPow2(bitmap.width);
                height = nextPow2(bitmap.rows);

                for (j = 0; j < height; ++j)
                {
                    for (i = 0; i < width; ++i)
                    {
                        fullData[offset + 2*(i+(j*fullWidth))] =
                        fullData[offset + 2*(i+(j*fullWidth))+1] =
                            (i >= bitmap.width || j >= bitmap.rows ) ?
                                0 : bitmap.buffer[i + (bitmap.width*j)];
                    }
                }

                //font.m_wids[aindex]=cast(float)(face.glyph.advance.x >> 6);
                font.m_xoffs[aindex]=cast(float)(face.glyph.metrics.horiBearingX >> 6);
                font.m_wids[aindex]=cast(float)(face.glyph.metrics.horiAdvance >> 6);

                auto hoss = cast(float)((face.glyph.metrics.horiBearingY -
                                         face.glyph.metrics.height) >> 6);

                vxlo = 0;
                vxhi = bitmap.width;
                vylo = hoss;
                vyhi = bitmap.rows + hoss;

                txlo = (index-32)/96.0f;
                txhi = txlo + (cast(float)bitmap.width/cast(float)maxWidth)/96.0f;
                tylo = 0;
                tyhi = (cast(GLfloat)bitmap.rows/cast(GLfloat)maxHeight);

                auto qvws = bitmap.width;
                auto qvhs = bitmap.rows;

                if (qvhs > font.m_maxHeight)
                    font.m_maxHeight = qvhs;
                if (font.m_wids[aindex] > font.m_maxWidth)
                    font.m_maxWidth = font.m_wids[aindex];
                if (abs(hoss) > font.m_maxHoss)
                    font.m_maxHoss = abs(hoss);

            }
            else
            {
                width = maxWidth;
                height = maxHeight;

                for (j = 0; j < height; ++j)
                {
                    for (i = 0; i < width; ++i)
                    {
                        fullData[offset + 2*(i+(j*fullWidth))] = 0;
                        fullData[offset + 2*(i+(j*fullWidth))+1] = 255;
                    }
                }

                vxlo = 0;
                vxhi = font.m_maxWidth;
                vylo = -font.m_maxHoss;
                vyhi = font.m_maxHeight;

                txlo = (index-32)/96.0f;
                txhi = txlo + (cast(float)maxWidth/cast(float)maxWidth)/96.0f;
                tylo = 0;
                tyhi = 1;
            }

            font.m_vertices[aindex*16 +  0] = vxlo;
            font.m_vertices[aindex*16 +  1] = vyhi;
            font.m_vertices[aindex*16 +  2] = txlo;
            font.m_vertices[aindex*16 +  3] = tylo;
            font.m_indices[aindex*4 + 0] = cast(GLushort)(aindex*4);

            font.m_vertices[aindex*16 +  4] = vxlo;
            font.m_vertices[aindex*16 +  5] = vylo;
            font.m_vertices[aindex*16 +  6] = txlo;
            font.m_vertices[aindex*16 +  7] = tyhi;
            font.m_indices[aindex*4 + 1] = cast(GLushort)(aindex*4 + 1);

            font.m_vertices[aindex*16 +  8] = vxhi;
            font.m_vertices[aindex*16 +  9] = vylo;
            font.m_vertices[aindex*16 + 10] = txhi;
            font.m_vertices[aindex*16 + 11] = tyhi;
            font.m_indices[aindex*4 + 2] = cast(GLushort)(aindex*4 + 2);

            font.m_vertices[aindex*16 + 12] = vxhi;
            font.m_vertices[aindex*16 + 13] = vyhi;
            font.m_vertices[aindex*16 + 14] = txhi;
            font.m_vertices[aindex*16 + 15] = tylo;
            font.m_indices[aindex*4 + 3] = cast(GLushort)(aindex*4 + 3);
	    }

        glBindTexture(GL_TEXTURE_2D, font.m_texture);
        glTexParameteri(GL_TEXTURE_2D, GL_TEXTURE_MAG_FILTER, GL_LINEAR);
        glTexParameteri(GL_TEXTURE_2D, GL_TEXTURE_MIN_FILTER, GL_LINEAR);

        glTexImage2D(GL_TEXTURE_2D, 0, GL_ALPHA16, fullWidth, fullHeight,
                     0, GL_LUMINANCE_ALPHA, GL_UNSIGNED_BYTE, fullData.ptr);

	    return 0;
    }

    // Create a font from a glyph file
    int createFont(FontGlyph fg, ref Font font)
	{
	    char i;
	    font.m_ptSize = fg.m_ptSize;
        font.m_wids.length = 96;
        font.m_xoffs.length = 96;
        glGenTextures(1, &font.m_texture);
	    font.m_vertices.length = 96 * 16; // 4*2 vtx + 4*2 tex
	    font.m_indices.length = 96 * 4;

        int maxHeight = 0;
        int maxWidth = 0;
        float maxHoss = 0;

        // Do a quick pass to find total width and height of the big texture
        int fullWidth = 0, fullHeight = 0;
        for (i = 32; i < 127; ++i)
	    {
            FT_Face face = fg.m_face;

            if (FT_Load_Glyph(face, FT_Get_Char_Index(face, i), FT_LOAD_DEFAULT))
                return -1;

            FT_Render_Glyph(face.glyph, FT_Render_Mode.FT_RENDER_MODE_NORMAL);
            FT_Bitmap bitmap = face.glyph.bitmap;

            int width = nextPow2(bitmap.width);
            int height = nextPow2(bitmap.rows);

            if (width > maxWidth)
                maxWidth = width;
            if (height > maxHeight)
                maxHeight = height;
	    }

        createFontTextures(fg, font, maxWidth, maxHeight);
	    font.m_lineHeight = 1.2*font.m_maxHeight;


        glGenBuffers(1, &font.m_vertexBuffer);
        glBindBuffer(GL_ARRAY_BUFFER, font.m_vertexBuffer);
        glBufferData(GL_ARRAY_BUFFER,
                     font.m_vertices.length * GLfloat.sizeof,
                     font.m_vertices.ptr,
                     GL_STATIC_DRAW);

        glGenBuffers(1, &font.m_indexBuffer);
        glBindBuffer(GL_ELEMENT_ARRAY_BUFFER, font.m_indexBuffer);
        glBufferData(GL_ELEMENT_ARRAY_BUFFER,
                     font.m_indices.length * GLushort.sizeof,
                     font.m_indices.ptr,
                     GL_STATIC_DRAW);
	    return 0;
	}

    // Clear out the textures from a font
	void clearFont(Font font)
	{
	    glDeleteTextures(1, &font.m_texture);
        font.m_wids.clear;
        font.m_vertices.clear;
        font.m_indices.clear;
	}


	// Delete an FT_Face
    void deleteFontGlyph(FontGlyph font)
    {
        FT_Done_Face(font.m_face);
    }


	// Calculate the next power of two
    uint nextPow2(uint i)
    {
        uint nextPow;
        for(nextPow = 1; nextPow < i; nextPow <<= 1) {}
        return nextPow;
    }

} // private functions
