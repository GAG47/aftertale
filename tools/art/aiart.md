~~~
$src = "D:\godotproject\aftertale\assets\art\source\head\head_v10"
$dst = "D:\godotproject\aftertale\assets\art\source\head\head_v10_"

New-Item -ItemType Directory -Force -Path $dst | Out-Null

Get-ChildItem $src -Recurse -File -Filter *.png |
Where-Object {
    $_.FullName -notlike "$dst\*" -and
    $_.Name -notlike "*副本*" -and
    $_.BaseName -notmatch '_(north|east|west)$'
} |
Copy-Item -Destination $dst -Force
~~~

~~~
$src = "D:\godotproject\ai-rpg\asset\hair"
$dst = "D:\godotproject\ai-rpg\asset\hair\front"

New-Item -ItemType Directory -Force -Path $dst | Out-Null

Get-ChildItem $src -Recurse -File -Filter *.png |
Where-Object {
    $_.FullName -notlike "$dst\*" -and
    $_.Name -notlike "*副本*" -and
    $_.BaseName -notmatch '_(north|east|westm)$'
} |
Copy-Item -Destination $dst -Force
~~~



**批量移动**

~~~
cd D:\godotproject\aftertale

powershell -NoProfile -ExecutionPolicy Bypass -File tools\art\set_character_batch_adjustment.ps1 `
  -BatchId "hair/hair_v4_" `
  -Part hair `
  -OffsetY -40 `
  -Scale 0.65
~~~

~~~
powershell -NoProfile -ExecutionPolicy Bypass -File tools\art\preview_character_batch.ps1 `
  -BatchId "hair/hair_v4_" `
  -Part hair `
  -MaxItems 100
~~~



~~~
cd D:\godotproject\aftertale

powershell -NoProfile -ExecutionPolicy Bypass -File tools\art\set_character_batch_adjustment.ps1 `
  -BatchId "apparel/apparel_v4_" `
  -Part outfit `
  -OffsetY 15 `
  -Scale 0.5
~~~

~~~
powershell -NoProfile -ExecutionPolicy Bypass -File tools\art\preview_character_batch.ps1 `
  -BatchId "apparel/apparel_v4_" `
  -Part outfit `
  -MaxItems 100
~~~



**导入**

~~~
cd D:\godotproject\aftertale

powershell -NoProfile -ExecutionPolicy Bypass -File tools\art\standardize_character_batch.ps1 `
  -BatchId "hair/hair_v4_" `
  -Part hair
~~~



**AI生成素材提示词**（环世界风格小人）

~~~
Use the uploaded body image as the exact template.

Draw clothing on this body and keep the exact body pose, front-facing south-facing direction, body size, and alignment.
Do not redesign the body. Do not create a different character.

Create a modular RPG outfit preview for this character.

Outfit target:
- outfit id: [OUTFIT_ID]
- group: [GROUP]
- outfit type: [OUTFIT_TYPE]
- leg mode: [hidden / partial / visible]
- main color: [MAIN_COLOR]
- secondary color: [SECONDARY_COLOR]
- accent color: [ACCENT_COLOR]
- key details: [KEY_DETAIL_1], [KEY_DETAIL_2]

Style:
- anime-style chibi game asset
- clean dark outline
- soft cel shading
- large readable shapes
- compact silhouette
- readable when scaled down to 64x64
- designed for a modular 2D RPG character

Rules:
- keep the uploaded body proportions
- keep the outfit compact
- if leg mode is hidden, the lower garment should cover the legs
- if leg mode is partial, only a little of the legs or feet may show
- if leg mode is visible, short legs may be visible
- no visible hands
- no weapon
- no held item
- no background scene
- no extra character
- no text
- no watermark
~~~

~~~
Use the uploaded body image as the exact alignment template.

Create ONLY a modular outfit layer for this chibi RPG character.
Do not draw a full character.
Do not draw the body skin, head, face, or hair.

This outfit layer must fit exactly over the uploaded body:
- keep the same front-facing south-facing alignment
- keep the same body proportions
- keep the same clothing position and scale
- leave the head area empty
- leave the neck opening or collar opening properly shaped for the body template

Outfit target:
- outfit id: [OUTFIT_ID]
- group: [GROUP]
- outfit type: [OUTFIT_TYPE]
- leg mode: [hidden / partial / visible]
- main color: [MAIN_COLOR]
- secondary color: [SECONDARY_COLOR]
- accent color: [ACCENT_COLOR]
- key details: [KEY_DETAIL_1], [KEY_DETAIL_2]

Visual style:
- anime-style chibi game asset
- clean dark outline
- soft cel shading
- compact silhouette
- clear readable shapes
- readable when scaled down to 64x64
- modular 2D RPG outfit asset

Rules:
- output clothing only
- no body skin
- no head
- no face
- no hair
- no visible hands
- no weapon
- no held item
- if leg mode is hidden, the outfit should cover the legs
- if leg mode is partial, the lower hem may allow only a small amount of leg or foot visibility
- if leg mode is visible, short legs may remain visible in the final fitted outfit shape
- keep the silhouette compact
- use only one or two strong profession-defining details
- no background scene
- no text
- no watermark
~~~



**AI生成素材提示词**（人物）

~~~
请生成一张日式幻想 SRPG 风格的角色全身立绘。

角色设定：
- 职业：{职业}
- 性别：{性别}
- 年龄感：{年龄感}
- 体型：{体型}
- 气质：{气质}
- 身份关键词：{身份关键词}

外观设定：
- 发型/发色：{发型发色}
- 瞳色：{瞳色}
- 面部特征：{面部特征}
- 种族/特征：{种族特征}

服装与装备：
- 服装风格：{服装风格}
- 主色调：{主色调}
- 材质构成：{材质构成}
- 装饰细节：{装饰细节}
- 武器/道具：{武器道具}

动作与构图：
- 构图：完整全身、单人、白色或纯净浅色背景
- 视角：正面或轻微 3/4 视角
- 姿势：{姿势}
- 表情：{表情}
- 角色轮廓清晰，职业特征一眼可辨

画风要求：
- 日式王道幻想 SRPG / JRPG 角色设定图风格
- 干净细致的动漫线稿
- 柔和赛璐璐上色，带少量淡彩质感
- 低饱和、自然、柔和的配色
- 中世纪轻幻想服装设计
- 布料、皮革、金属材质区分明确
- 画面清爽，适合游戏角色立绘与 UI 展示
- 不要复杂背景，不要强烈特效，不要夸张透视

额外要求：
- 角色设计要有明确职业辨识度
- 服装既有设计感，也要有一定实用性
- 整体气质偏温和、冒险感、王道幻想
- 保持比例自然，人体结构正确，手部清晰

避免：
- 现代服装
- 科幻元素
- 赛博朋克
- 3D 渲染感
- 过度写实
- 厚重油画感
- 高饱和霓虹色
- 杂乱背景
- 动态战斗场面
~~~

