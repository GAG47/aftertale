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

~~~
生成一张日式幻想 SRPG 风格的角色全身立绘。

角色是一名{职业}，{性别}，年龄感约 {年龄感}，体型 {体型}，整体气质 {气质}，身份关键词为 {身份关键词}。角色拥有 {发型发色}、{瞳色}、{面部特征}，并带有 {种族特征}。穿着 {服装风格}，主色调为 {主色调}，材质包含 {材质构成}，配有 {装饰细节}，手持 {武器道具}。

请绘制为完整全身、单人、白色背景，正面或轻微 3/4 视角，姿势 {姿势}，表情 {表情}，角色轮廓清晰，职业特征一眼可辨。

画风统一为：日式幻想 SRPG / JRPG 角色设定图风格，干净清晰的动漫线稿，外轮廓线加粗，线条层级分明，角色剪影清楚，柔和赛璐璐上色，轻微淡彩质感，低饱和自然柔和配色，中世纪轻幻想服装设计，布料、皮革、金属材质区分明确，画面清爽，适合游戏角色立绘与 UI 展示

避免：现代服装、科幻元素、赛博朋克、3D 建模感、过度写实、厚重厚涂、复杂背景、强烈特效、夸张透视、手部崩坏、人体比例异常。
~~~

~~~
请根据原角色立绘，生成同一角色的战棋 / SRPG 地图单位小人版本。

角色是一名{职业}，{性别}，整体气质{气质}，身份关键词为{身份关键词}。请保留原角色的关键识别特征：{发型发色}、{瞳色}、{面部特征}、{种族特征}；保留核心服装元素：{服装风格}；保留主色调：{主色调}；保留标志性装备：{武器道具}；保留关键装饰细节：{装饰细节}。

请将角色改写为战棋 / SRPG 地图单位风格的小人：SD / Q版比例，约 2.5~3.5 头身，完整全身，单人，白色背景，正面或轻微 3/4 视角，姿势为{姿势}，表情为{表情}。角色需要轮廓清晰，细节简化，适合小尺寸地图显示，并且职业特征一眼可辨。

画风统一为：日式幻想 SRPG / JRPG 地图单位风格，干净清晰的动漫线稿，外轮廓线明显加粗，线条层级分明，角色剪影清楚，柔和赛璐璐上色，简洁明确的阴影，低饱和自然柔和配色，中世纪轻幻想服装设计，适合游戏地图与 UI 显示，看起来像战棋游戏中的角色单位，而不是正式角色立绘或普通Q版插画。

避免：复杂背景、场景元素、过多特效、夸张动作、轮廓混乱、写实风、3D 建模感、现代服装、科幻元素、过度复杂服饰细节、人体比例异常、手部崩坏。
~~~

~~~
请基于当前这张 Q 版角色图继续简化，保持同一角色身份与核心特征不变，但将其进一步优化为适合战棋 / SRPG 地图单位显示的小尺寸版本。保留 {核心发型发色}、{核心瞳色}、{核心种族特征}、{核心服装主轮廓}、{核心主色调}、{核心武器} 和 {核心气质}，其余细节尽量收敛。请显著减少小饰品、小挂件、复杂花纹、细碎边饰和过密层次，让服装、武器和配件更概括、更整洁、更偏大色块与大轮廓。{次要配件A} 和 {次要配件B} 只保留基础识别，不要复杂纹样。请明显强化加粗外轮廓，减少内部细线，让角色缩小到 64px~96px 时依然一眼能看出职业与身份。完整全身，单人，纯白背景，轻微 3/4 视角，{待机姿势描述}，柔和赛璐璐上色，低饱和自然配色，整体必须更像高可读性的战棋地图单位，而不是精细 Q 版立绘。
~~~

~~~
请将这张图的纯白色背景修改为纯色亮绿色绿幕背景（#00FF00）。只替换背景颜色，角色本体、线稿、颜色、阴影、细节、姿势、表情、武器和服装全部保持不变。背景必须是单一纯色亮绿色。 
~~~





~~~
生成一张日式幻想 SRPG 风格的角色全身立绘。

角色是一名法师，女性，年龄感约 16~20 岁，体型纤细轻盈，整体气质温柔、聪慧、神秘，身份关键词为 学院法师、元素使、旅途中的施法者。角色拥有浅粉色短发、淡紫色瞳色、表情柔和且眼神清澈，并带有小角与轻微魔法纹样特征。穿着宽袖短斗篷法袍与层叠布料的轻幻想魔法服饰，主色调为 米白、浅灰、淡金、少量青蓝，材质包含布料、皮革、少量宝石与金属饰件，配有披肩、胸针、吊坠、符文纹样、小包，手持木制法杖与魔导书。

请绘制为完整全身、单人、纯白背景，正面或轻微 3/4 视角，姿势为自然站姿，一只手轻抬像在引导魔力，表情安静、柔和、略带好奇，角色轮廓清晰，职业特征一眼可辨。

画风统一为：日式幻想 SRPG / JRPG 地图单位风格，干净清晰的动漫线稿，外轮廓线明显加粗，线条层级分明，角色剪影清楚，柔和赛璐璐上色，简洁明确的阴影，低饱和自然柔和配色，中世纪轻幻想服装设计，适合游戏地图与 UI 显示，看起来像战棋游戏中的角色单位，而不是正式角色立绘或普通Q版插画。

避免：复杂背景、场景元素、过多特效、夸张动作、轮廓混乱、写实风、3D 建模感、现代服装、科幻元素、过度复杂服饰细节、人体比例异常、手部崩坏。
~~~

~~~
请根据同一角色的设定，生成一个用于战棋 / SRPG 地图上的角色小人。

角色是一名法师，女性，年龄感约 16~20 岁，体型纤细轻盈，整体气质温柔、聪慧、神秘，身份关键词为 学院法师、元素使、旅途中的施法者。请保留角色的关键识别特征：浅粉色短发、淡紫色瞳色、表情柔和且眼神清澈、小角与轻微魔法纹样特征；保留核心服装元素：宽袖短斗篷法袍与层叠布料的轻幻想魔法服饰；保留主色调：米白、浅灰、淡金、少量青蓝；保留材质特征：布料、皮革、少量宝石与金属饰件；保留关键装饰细节：披肩、胸针、吊坠、符文纹样、小包；保留标志性装备：木制法杖与魔导书。

请将角色绘制为战棋 / SRPG 地图单位风格的小人：SD / Q版比例，约 2.5~3.5 头身，完整全身，单人，纯白背景，正面或轻微 3/4 视角，姿势为持法杖的待机站姿，一只手微抬，表情安静、柔和、略带好奇。角色需要轮廓清晰，细节简化，武器和法师职业特征一眼可辨，适合放在地图格子中显示，适合小尺寸游戏地图与 UI 使用。 

画风统一为：日式幻想 SRPG / JRPG 地图单位风格，干净清晰的动漫线稿，外轮廓线明显加粗，线条层级分明，角色剪影清楚，柔和赛璐璐上色，简洁明确的阴影，低饱和自然柔和配色，中世纪轻幻想服装设计，适合游戏地图与 UI 显示，看起来像战棋游戏中的角色单位，而不是正式角色立绘或普通Q版插画。 

避免：复杂背景、场景元素、过多特效、夸张动作、轮廓混乱、写实风、3D 建模感、现代服装、科幻元素、过度复杂服饰细节、人体比例异常、手部崩坏。
~~~

~~~
请基于当前这张法师 Q 版角色图继续优化，并在保持同一角色身份不变的前提下，再做一轮明显简化。保留角色最核心的识别特征，包括浅粉色短发、淡紫色眼睛、小角、白色与浅金色为主的法师服装、木制法杖以及温柔安静的气质，但请把整体进一步调整为更适合战棋 / SRPG 地图单位显示的小尺寸角色。重点是提升缩小到 64px~96px 高度时的可读性，而不是追求大图状态下的精致复杂感。请明显减少细碎装饰和密集花纹，弱化或删除过小的挂件、链条、零碎边饰、复杂金色纹样、靴子与衣摆上的小装饰，腰间的小包和书本也请进一步概括化与简化，书本保留“法师书”的大形体识别即可，不要复杂封面纹样。法杖顶部请简化为更清楚的大形体结构，保留木杖与蓝色晶体的辨识特征，但减少细小枝叶、吊饰和复杂边角。整体服装请保留白袍法师的大轮廓、披肩与宽袖的主要结构，但下摆和袖口的细节请收敛，让主色块更明确，轮廓更干净。请使用更强的外轮廓线，内部线条更少更简洁，确保头部、法杖、袖子和衣袍轮廓非常清楚。画风仍然保持日式幻想 SRPG / JRPG 地图单位风格，柔和赛璐璐上色，低饱和自然柔和配色，完整全身，单人，纯白背景，轻微 3/4 视角，待机站姿，整体看起来像真正适合放进战棋地图中的高可读性法师单位，而不是精致但缩小后容易糊成一团的 Q 版插画。
~~~
